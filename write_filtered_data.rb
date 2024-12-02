# frozen_string_literal: true
require 'set'
require_relative 'order_shipment_data'
require_relative 'barcode_location'
require_relative './shipments/forward_shipment'
require_relative './shipments/return_shipment'
require_relative 'invalid_order_filters'
class WriteFilteredData
  @project_root = File.expand_path("..", __dir__)

  def self.run_methods
    invalid_single_barcode_orders
    invalid_single_barcode_orders(true)
    invalid_multiple_barcode_orders
    invalid_multiple_barcode_orders(true)
  end

  def self.invalid_single_barcode_orders(with_returns = false)
    invalid_orders_data = []
    invalid_orders = InvalidOrderFilters.get_orders_with_no_barcodes(with_returns)
    ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = BarcodeLocation.find_by_barcode(shipment_line.barcode)
        if invalid_orders and invalid_orders.include?(forward_shipment.parent_order_id)
          invalid_orders_data << {
            fulfilment_location: shipment_line.fulfilment_location,
            parent_order_code: forward_shipment.parent_order_id,
            shipment_id: shipment_line.shipment_id,
            sku: shipment_line.sku,
            barcode: shipment_line.barcode,
            barcode_location: barcode_location ? barcode_location.first.location : nil,
            quantity: barcode_location ? barcode_location.first.quantity : 0
          }
        end
      end
    end
    if with_returns
      write_orders_to_text_file(invalid_orders_data, "#{@project_root}/results/invalid_orders/single_barcode_with_returns.csv")
    else
      write_orders_to_text_file(invalid_orders_data, "#{@project_root}/results/invalid_orders/single_barcode_without_returns.csv")
    end
    invalid_orders_data
  end

  def self.invalid_multiple_barcode_orders(with_returns = false)
    invalid_orders_data = []
    invalid_orders = InvalidOrderFilters.get_orders_with_multiple_barcodes(with_returns)
    ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
      forward_shipment.shipment_lines.each do |shipment_line|
        barcode_location = BarcodeLocation.find_by_barcode(shipment_line.barcode)
        if invalid_orders and invalid_orders.include?(forward_shipment.parent_order_id)
          invalid_orders_data << {
            fulfilment_location: shipment_line.fulfilment_location,
            parent_order_code: forward_shipment.parent_order_id,
            shipment_id: shipment_line.shipment_id,
            sku: shipment_line.sku,
            barcode: shipment_line.barcode,
            barcode_location: barcode_location ? barcode_location.first.location : nil,
            quantity: barcode_location ? barcode_location.first.quantity : 0
          }
        end
      end
    end
    if with_returns
      write_orders_to_text_file(invalid_orders_data, "#{@project_root}/results/invalid_orders/multiple_barcode_with_returns.csv")
    else
      write_orders_to_text_file(invalid_orders_data, "#{@project_root}/results/invalid_orders/multiple_barcode_without_returns.csv")
    end
    invalid_orders_data
  end

  def write_orders_to_text_file(orders, file_name, is_return = false)
    if is_return
      File.open(file_name, 'w') do |file|
        file.puts 'Parent Order Code,Return Order Code,Location'
        orders.each do |order|
          file.puts "#{order.forward_shipment.parent_order_id},#{order.return_order_code},#{order.location.full_name}"
        end
      end
    else
      File.open(file_name, 'w') do |file|
        file.puts 'Fulfilment Location,Parent Order Code,Shipment ID,Barcode,SKU,Barcode Location,Quantity'
        orders.each do |order|
          file.puts "#{order[:fulfilment_location]},#{order[:parent_order_code]},#{order[:shipment_id]},#{order[:barcode]},#{order[:sku]},#{order[:barcode_location]},#{order[:quantity]}"
        end
      end
    end
  end
end
