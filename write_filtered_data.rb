# frozen_string_literal: true
require 'set'
require_relative 'order_shipment_data'
require_relative 'barcode_location'
require_relative './shipments/forward_shipment'
require_relative './shipments/return_shipment'
require_relative 'invalid_order_filters'
require_relative 'const'

class WriteFilteredData

  @project_root = Const::PROJECT_ROOT
  @result_direct = Const::RESULT_DIRECT

  class << self

    def run_methods
      invalid_single_barcode_orders
      invalid_single_barcode_orders(true)
      invalid_multiple_barcode_orders
      invalid_multiple_barcode_orders(true)
    end

    def invalid_single_barcode_orders(with_returns = false)
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
              barcode_location: if barcode_location
                                  barcode_location.size > 1 ? "barcode in multiple location" : barcode_location.first.location
                                else
                                  nil
                                end,
              quantity: barcode_location ? barcode_location.first.quantity : 0
            }
          end
        end
      end
      if with_returns
        write_orders_to_text_file(invalid_orders_data, "#{@result_direct}invalid_orders/with_returns/single_barcode_with_returns.csv")
      else
        write_orders_to_text_file(invalid_orders_data, "#{@result_direct}invalid_orders/without_returns/single_barcode_without_returns.csv")
      end
      invalid_orders_data
    end

    def invalid_multiple_barcode_orders(with_returns = false)
      invalid_orders_data = []
      invalid_orders = InvalidOrderFilters.get_orders_with_multiple_barcodes(with_returns)
      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        completed_shipments = OrderShipmentData.shipment_data_by_parent_order_code[forward_shipment.parent_order_id]
        forward_shipment.shipment_lines.each do |shipment_line|
          barcode_location = BarcodeLocation.find_by_barcode(shipment_line.barcode)
          if invalid_orders and invalid_orders.include?(forward_shipment.parent_order_id)
            next if completed_shipments.include? shipment_line.shipment_id
            invalid_orders_data << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: if barcode_location
                                  barcode_location.size > 1 ? "barcode in multiple location" : barcode_location.first.location
                                else
                                  nil
                                end,
              quantity: barcode_location ? barcode_location.first.quantity : 0
            }
          end
        end
      end
      if with_returns
        write_orders_to_text_file(invalid_orders_data, "#{@result_direct}invalid_orders/with_returns/multiple_barcode_with_returns.csv")
      else
        write_orders_to_text_file(invalid_orders_data, "#{@result_direct}invalid_orders/without_returns//multiple_barcode_without_returns.csv")
      end
      invalid_orders_data
    end

    def get_valid_forward_orders_with_returns(is_shipment_level = false)
      valid_orders = []

      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        shipments = ValidOrderFilters.valid_forward_shipment?(forward_shipment, is_shipment_level)
        next unless shipments
        forward_shipment.shipment_lines.each do |shipment_line|
          barcode_location = ValidOrderFilters.get_valid_barcode_location(shipment_line)
          next unless barcode_location
          if is_shipment_level
            should_add = shipments.include?(shipment_line.shipment_id)
          else
            should_add = shipments
          end

          if should_add
            valid_orders << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: barcode_location.location,
              quantity: barcode_location.quantity
            }
          end
        end
      end

      file_name = "#{@result_direct}valid_orders#{'(shipment_level)' if is_shipment_level}.csv"
      write_orders_to_text_file(valid_orders, file_name)
      valid_orders
    end

    def get_orders_with_wrong_barcode_location_with_returns(is_shipment_level = false)
      partial_availability_orders = []

      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        shipments = ValidOrderFilters.partial_valid_shipment?(forward_shipment, is_shipment_level)
        next unless shipments
        forward_shipment.shipment_lines.each do |shipment_line|
          barcode_location = ValidOrderFilters.get_partial_valid_barcodes(shipment_line)
          next unless barcode_location
          if is_shipment_level
            should_add = shipments.include?(shipment_line.shipment_id)
          else
            should_add = shipments
          end

          if should_add
            partial_availability_orders << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: barcode_location.location,
              quantity: barcode_location.quantity
            }
          end
        end
      end

      file_name = "#{@result_direct}needs_sto/partial_availability_orders#{'(shipment_level)' if is_shipment_level}.csv"
      write_orders_to_text_file(partial_availability_orders, file_name)
      partial_availability_orders
    end

    def get_orders_without_returns_at_right_location(is_shipment_level = false)
      forwards_without_returns = []

      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        shipments = ValidOrderFilters.valid_shipment_without_returns?(forward_shipment, is_shipment_level)
        next unless shipments
        forward_shipment.shipment_lines.each do |shipment_line|
          barcode_location = ValidOrderFilters.get_valid_barcode_location(shipment_line)
          next unless barcode_location

          if is_shipment_level
            should_add = shipments.include?(shipment_line.shipment_id)
          else
            should_add = shipments
          end

          if should_add
            forwards_without_returns << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: barcode_location.location,
              quantity: barcode_location.quantity
            }
          end
        end
      end

      file_name = "#{@result_direct}forwards_without_returns#{'(shipment_level)' if is_shipment_level}.csv"

      write_orders_to_text_file(forwards_without_returns, file_name)
      forwards_without_returns
    end

    def get_partial_valid_orders_without_returns(is_shipment_level = false)
      partial_valid_orders = []

      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        shipments = ValidOrderFilters.partial_valid_shipment_without_returns?(forward_shipment, is_shipment_level)
        next unless shipments
        forward_shipment.shipment_lines.each do |shipment_line|
          barcode_location = ValidOrderFilters.get_partial_valid_barcodes(shipment_line)
          next unless barcode_location
          if is_shipment_level
            should_add = shipments.include?(shipment_line.shipment_id)
          else
            should_add = shipments
          end

          if should_add
            partial_valid_orders << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: barcode_location.location,
              quantity: barcode_location.quantity
            }
          end
        end
      end

      file_name = "#{@result_direct}needs_sto/partial_valid_orders_without_returns#{'(shipment_level)' if is_shipment_level}.csv"
      write_orders_to_text_file(partial_valid_orders, file_name)
      partial_valid_orders
    end

    def get_partially_completed_orders(is_shipment_level = true)
      partial_valid_orders = []

      ForwardShipment.forward_shipments_by_parent_id.each_value do |forward_shipment|
        # shipments: either boolean or array of shipment_ids, depending on is_shipment_level
        shipments = ValidOrderFilters.incomplete_order_shipments(forward_shipment, is_shipment_level)
        next unless shipments

        forward_shipment.shipment_lines.each do |shipment_line|
          if forward_shipment.parent_order_id == 'KO206755'
            p 'KO206755'
          end

          next if shipment_line.barcode.nil?

          # If is_shipment_level is true, only process lines whose shipment_id is in shipments
          if is_shipment_level
            next unless shipments.keys.include?([shipment_line.shipment_id.to_s, shipment_line.sku])
          end

          barcode_location = BarcodeLocation.find_by_barcode(shipment_line.barcode)

          # Push the record into partial_valid_orders
          barcodes = OrderShipmentData.find_barcodes_by_shipment_and_sku(shipment_line.shipment_id, shipment_line.sku)
          unless barcodes.include?(shipment_line.barcode)

            partial_valid_orders << {
              fulfilment_location: shipment_line.fulfilment_location,
              parent_order_code: forward_shipment.parent_order_id,
              shipment_id: shipment_line.shipment_id,
              sku: shipment_line.sku,
              barcode: shipment_line.barcode,
              barcode_location: if barcode_location
                                  barcode_location.size > 1 ? "barcode in multiple location" : barcode_location.first.location
                                else
                                  nil
                                end,
              quantity: barcode_location ? barcode_location.first.quantity : 0
            }
          end
        end
      end

      # Write to CSV (or any file)
      write_orders_to_text_file(partial_valid_orders, "#{@result_direct}partially_completed_orders.csv")
      partial_valid_orders
    end

    def write_orders_to_text_file(orders, file_name, is_return = false)
      if is_return
        headers = ['Parent Order Code', 'Return Order Code', 'Location']
      else
        headers = ['Fulfilment Location', 'Parent Order Code', 'Shipment ID', 'Barcode', 'SKU', 'Barcode Location', 'Quantity']
      end

      CSV.open(file_name, 'w', write_headers: true, headers: headers) do |csv|
        if is_return
          orders.each do |order|
            csv << [
              order.forward_shipment.parent_order_id,
              order.return_order_code,
              order.location.full_name
            ]
          end
        else
          orders.each do |order|
            csv << [
              order[:fulfilment_location],
              order[:parent_order_code],
              order[:shipment_id],
              order[:barcode],
              order[:sku],
              order[:barcode_location],
              order[:quantity]
            ]
          end
        end
      end
    end
  end
end
