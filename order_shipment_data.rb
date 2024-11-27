# frozen_string_literal: true
require 'csv'
require_relative 'pending_forward'

class OrderShipmentData
  attr_accessor :parent_order_code, :shipment_id

  @shipment_data_by_parent_order_code = Hash.new { |h, k| h[k] = [] }

  class << self
    attr_accessor :shipment_data_by_parent_order_code

    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        parent_order_code = row['external_parent_order_code']
        shipment_id = row['external_shipment_id']

        if row['is_completed'] == true
          next unless PendingForward.pending?(parent_order_code)
          OrderShipmentData.new(parent_order_code, shipment_id)
        end
      end

      def find_by_parent_order_coder_and_shipment_code(parent_order_code)
        @shipment_data_by_parent_order_code[parent_order_code]
      end

    end
  end

  def initialize(parent_order_code, shipment_id)
    @parent_order_code = parent_order_code
    @shipment_id = shipment_id

    self.class.shipment_data_by_parent_order_code[parent_order_code] << shipment_id

  end
end
