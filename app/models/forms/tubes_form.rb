#This file is part of Illumina-B Pipeline is distributed under the terms of GNU General Public License version 3 or later;
#Please refer to the LICENSE and README files for information on licensing and authorship of this file.
#Copyright (C) 2011,2012 Genome Research Ltd.
module Forms
  class TubesForm < CreationForm

    class Sibling

      READY_STATE = 'qc_complete'

      attr_reader :name, :uuid, :state, :barcode

      def initialize(options)
        return missing_sibling unless options.respond_to?(:[])
        @name = options['name']
        @uuid = options['uuid']
        @barcode = options['ean13_barcode']
        @state = options['state']
      end

      def message
        return 'This tube is ready for pooling, find it, and scan it in above' if state == READY_STATE
        return 'Some requests still need to be progressed to appropriate tubes' if state == 'Not Present'
        'Must be %s first' % READY_STATE
      end

      def ready?
        state == READY_STATE
      end

      private
      def missing_sibling
        @name  = 'Other'
        @state = 'Not Present'
      end
    end

    def render(controller)
      if no_pooling_required?
        super
      else
        controller.render(self.page)
      end
    end

    attr_reader :all_tube_transfers

    def no_pooling_required?
      tube.sibling_tubes.count == 1
    end

    def siblings
      @siblings ||= tube.sibling_tubes.map {|s| Sibling.new(s) }
    end

    def each_sibling
      siblings.each {|s| yield s }
    end

    def all_ready?
      siblings.all?(&:ready?)
    end

    def barcode_to_uuid(barcode)
      siblings.detect {|s| s.barcode == barcode }.uuid
    end

    write_inheritable_attribute :page, 'multi_tube_pooling'
    write_inheritable_attribute :attributes, [:api, :purpose_uuid, :parent_uuid, :user_uuid, :parents]

    validate :all_parents_and_only_parents?, :if => :barcodes_provided?

    def create_objects!
      success = []
      @all_tube_transfers = parents.map do |this_parent_uuid|
        transfer_template.create!(
          :user   => user_uuid,
          :source => this_parent_uuid
        ).tap { success << this_parent_uuid }
      end
      true
    rescue => exception
      errors.add(:base,"#{success.count} tubes were transferred successfully before something went wrong." )
      errors.add(:base,e.message)
      false
    end

    # We pretend that we've added a new blank tube when we're actually
    # transfering to the tube on the original LibraryRequest
    def child
      return :contents_not_transfered_to_mx_tube if all_tube_transfers.nil?
      destination_uuids = all_tube_transfers.map do |tt|
        tt.destination.uuid
      end.uniq
      return all_tube_transfers.first.destination if destination_uuids.one?
      raise StandardError, 'Multiple targets found. You may have scanned tubes from separate submissions.'
    end

    def parents=(barcode_hash)
      return unless barcode_hash.respond_to?(:keys)
      @barcodes = barcode_hash.select {|barcode,selected| selected == "1" }.keys
      @parents = @barcodes.map {|barcode| barcode_to_uuid(barcode) }
    end

    def parent
      @parent ||= api.tube.find(parent_uuid)
    end
    alias_method(:tube, :parent)

    def parents
      @parents || [ parent_uuid ]
    end

    private

    def barcodes_provided?
      @barcode_hash.present?
    end

    def all_parents_and_only_parents?
      val_barcodes = @barcodes.dup
      valid = true
      siblings.each do |s|
        next if val_barcodes.delete(s.barcode)
        errors.add(:base,"Tube #{s.name} was missing. No transfer has been performed. This is a bug, as you should have been prevented from getting this far.")
        valid = false
      end
      return valid if val_barcodes.empty?
      errors.add(:base,"#{val_barcodes.join(', ')} barcodes are not valid. No transfer has been performed. This is a bug, as you should have been prevented from getting this far.")
      false
    end

    def transfer_template
      @template ||= api.transfer_template.find(
        Settings.transfer_templates["Transfer from tube to tube by submission"]
      )
    end

  end
end
