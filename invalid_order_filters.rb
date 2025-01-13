require 'set'
require_relative 'order_shipment_data'
require_relative 'barcode_location'
require_relative './shipments/forward_shipment'
require_relative './shipments/return_shipment'
require_relative 'write_filtered_data'

class InvalidOrderFilters

  def self.get_orders_with_multiple_barcodes(with_returns = false)
    invalid_orders = Set.new
    ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|

      completed_shipments = OrderShipmentData.shipment_data_by_parent_order_code[forward_shipment.parent_order_id]

      if forward_shipment.shipment_lines.size > 1
        forward_shipment.shipment_lines.each do |shipment_line|

          next if completed_shipments.include? shipment_line.shipment_id

          barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
          next unless barcode_locations.nil? || invalid_barcode(barcode_locations)

          return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
          next if with_returns == return_shipments.empty?

          invalid_orders.add(forward_shipment.parent_order_id)
        end
      end
    end
    invalid_orders
  end

  def self.get_orders_with_no_barcodes(with_returns = false)
    invalid_orders = Set.new
    ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|

      completed_shipments = OrderShipmentData.shipment_data_by_parent_order_code[forward_shipment.parent_order_id]

      if forward_shipment.shipment_lines.size == 1
        forward_shipment.shipment_lines.each do |shipment_line|

          next if completed_shipments.include? shipment_line.shipment_id

          barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
          next unless barcode_locations.nil?

          return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
          next if with_returns == return_shipments.empty?

          invalid_orders.add(forward_shipment.parent_order_id)
        end
      end
    end
    invalid_orders
  end

  def self.invalid_barcode(barcode_locations)
    if barcode_locations.size > 1 || barcode_locations.first.quantity != 1
      true
    else
      false
    end
  end

  def self.get_valid_barcode_location(shipment_line)
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations
    barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
    barcode_location if barcode_location && barcode_location.quantity == 1
  end


end

