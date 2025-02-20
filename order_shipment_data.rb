# frozen_string_literal: true
require 'csv'
require_relative 'pending_forward'

class OrderShipmentData
  attr_accessor :parent_order_code, :shipment_id, :sku, :barcode

  @shipment_data_by_parent_order_code = Hash.new { |h, k| h[k] = Set.new }
  @barcodes_by_shipment_and_sku = Hash.new { |hash, key| hash[key] = [] }

  class << self
    attr_accessor :shipment_data_by_parent_order_code, :barcodes_by_shipment_and_sku

    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        parent_order_code = row['external_parent_order_code']
        sku = row['sku']
        barcode = row['barcode']
        shipment_id = row['external_shipment_id']

        next if row['state'] != 'done'
        OrderShipmentData.new(parent_order_code, shipment_id.to_s, sku, barcode)
      end


    end
    def find_shipments_by_parent_order_code(parent_order_code)
      @shipment_data_by_parent_order_code[parent_order_code]
    end

    def find_barcodes_by_shipment_and_sku(shipment_id, sku)
      key = [shipment_id, sku]
      @barcodes_by_shipment_and_sku[key]
    end

  end

  def initialize(parent_order_code, shipment_id, sku, barcode)
    @parent_order_code = parent_order_code
    @sku = sku
    @barcode = barcode
    @shipment_id = shipment_id

    self.class.shipment_data_by_parent_order_code[parent_order_code].add(shipment_id)

    key = [shipment_id, sku]
    self.class.barcodes_by_shipment_and_sku[key] << barcode
  end
end
