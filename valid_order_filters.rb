# frozen_string_literal: true
require_relative 'shipments/forward_shipment'
require_relative 'shipments/return_shipment'
require_relative 'order_shipment_data'
require_relative 'location'
require_relative 'barcode_location'
require_relative 'pending_forward'

class ValidOrderFilters
  def self.valid_forward_shipment?(forward_shipment, is_shipment_level = false)
    valid_shipments = []
    invalid_shipment = Set.new
    forward_shipment.shipment_lines.each do |shipment_line|

      next if invalid_shipment.include?(shipment_line.shipment_id)

      is_shipment_done = OrderShipmentData.find_shipments_by_parent_order_code(forward_shipment.parent_order_id)
      if is_shipment_done.include?(shipment_line.shipment_id)
        if OrderShipmentData.find_barcodes_by_shipment_and_sku(shipment_line.shipment_id, shipment_line.sku)
          invalid_shipment << shipment_line.shipment_id
          next if is_shipment_level
          return false
        end
      end

      # Condition 1: Check for return shipments using parent_order_id, SKU, and barcode
      return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
      # p return_shipments unless return_shipments.empty?
      if return_shipments.empty?
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Iterate over all matching return shipments
      matching_return_found = return_shipments.any? do |return_shipment|
        return_shipment.shipment_lines.all? { |line| line.sku == shipment_line.sku && line.barcode == shipment_line.barcode }
      end
      unless matching_return_found
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Condition 2: Barcode location should match the fulfillment location
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations && barcode_locations.any? { |bl| (bl.location == shipment_line.fulfilment_location) and (bl.quantity == 1) }
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Condition 3: Validate quantity for the barcode in the location
      barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
      unless barcode_location && barcode_location.quantity == 1
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Condition 5: Ensure return exists at barcode level for any of the return shipments
      return_shipment_barcode_match = return_shipments.any? do |return_shipment|
        return_shipment.shipment_lines.all? { |line| line.barcode == shipment_line.barcode }
      end
      unless return_shipment_barcode_match
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      valid_shipments << shipment_line.shipment_id

    end
    return true unless is_shipment_level
    return false if valid_shipments.empty?

    valid_shipments - invalid_shipment.to_a
  end

  def self.partial_valid_shipment?(forward_shipment, is_shipment_level = false)
    valid_shipments = []
    invalid_shipment = Set.new
    forward_shipment.shipment_lines.each do |shipment_line|

      next if invalid_shipment.include?(shipment_line.shipment_id)

      is_shipment_done = OrderShipmentData.find_shipments_by_parent_order_code(forward_shipment.parent_order_id)
      if is_shipment_done.include?(shipment_line.shipment_id)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Check for return shipments for the current forward shipment
      return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
      if return_shipments.empty?
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
      # unless forward_shipments.count > 1
      #   invalid_shipment << shipment_line.shipment_id
      #   next if is_shipment_level
      #   return false
      # end

      # Get all locations for the barcode
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Ensure that at least one return shipment matches the barcode
      matching_return_found = return_shipments.any? do |return_shipment|
        return_shipment.shipment_lines.any? { |line| line.barcode == shipment_line.barcode }
      end
      unless matching_return_found
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      if barcode_locations.size > 1
        if barcode_locations.none? { |bl| bl.quantity == 0 }
          invalid_shipment << shipment_line.shipment_id
          next if is_shipment_level
          return false
        end

        barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
        if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
          invalid_shipment << shipment_line.shipment_id
          next if is_shipment_level
          return false
        end
      end

      # Validate if the barcode has a valid quantity in any location
      valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
      unless valid_quantity_location
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      valid_shipments << shipment_line.shipment_id
    end

    return true unless is_shipment_level
    return false if valid_shipments.empty?

    valid_shipments - invalid_shipment.to_a
  end

  def self.partial_valid_shipment_without_returns?(forward_shipment, is_shipment_level = false)
    valid_shipments = []
    invalid_shipment = Set.new
    forward_shipment.shipment_lines.each do |shipment_line|

      return false if shipment_line.barcode.nil?

      next if invalid_shipment.include?(shipment_line.shipment_id)

      return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
      unless return_shipments.empty?
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      is_shipment_done = OrderShipmentData.find_shipments_by_parent_order_code(forward_shipment.parent_order_id)
      if is_shipment_done.include?(shipment_line.shipment_id)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      unless barcode_locations
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
      unless forward_shipments.count > 1
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      if barcode_locations.size > 1
        barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
        if barcode_location && (barcode_location.quantity < 0 || barcode_location.quantity > 1)
          invalid_shipment << shipment_line.shipment_id
          next if is_shipment_level
          return false
        end
      end

      # Validate if the barcode has a valid quantity in any location
      valid_quantity_location = barcode_locations.find { |bl| bl.quantity == 1 }
      unless valid_quantity_location
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      valid_shipments << forward_shipment
    end

    return true unless is_shipment_level
    return false if valid_shipments.empty?

    valid_shipments - invalid_shipment.to_a
  end

  def self.valid_shipment_without_returns?(forward_shipment, is_shipment_level = false)
    valid_shipments = []
    invalid_shipment = Set.new
    forward_shipment.shipment_lines.each do |shipment_line|

      next if invalid_shipment.include?(shipment_line.shipment_id)

      return_shipments = ReturnShipment.find_by_forward_shipment(forward_shipment)
      unless return_shipments.empty?
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      is_shipment_done = OrderShipmentData.find_shipments_by_parent_order_code(forward_shipment.parent_order_id)
      if is_shipment_done.include?(shipment_line.shipment_id)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Check for valid barcode locations
      unless get_valid_barcode_location(shipment_line)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      # Check if the barcode is associated with multiple shipments
      if ForwardShipment.find_by_barcode(shipment_line.barcode).size > 1
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end

      valid_shipments << shipment_line.shipment_id
    end

    return true unless is_shipment_level
    return false if valid_shipments.empty?

    valid_shipments - invalid_shipment.to_a
  end

  def self.incomplete_order_shipments(forward_shipment, is_shipment_level = true)
    valid_shipments = Hash.new { |hash, key| hash[key] = [] }
    invalid_shipment = Set.new
    ignore_orders = %w[KO203749 KO207049 KO209814 KO215337 KO216554 29c46727-11e6-4eb7-a1d1-461e9200d4b3 KO212134 c32150f7-7f27-4994-990b-6444f4c1fcca 106de7f1-4776-4276-a463-41718912ac6c KO234218 KUS5867 KUS5656 KUS5666 KUS5913 KUS5727 KUS6020 KUS5994 KUS5863 1cdb4374-24da-42ba-bae9-b7472030ec17 KO206255 16b50037-cdca-4185-9f8b-7655f36551b1 KO227165 c5311dbb-acb1-4db4-9da8-fa1bd6147d62 KO222877 KO216986 KO220851 KO221620 KO205891 KO215646 KO220263 KO221297 KO223107 KO205285 dd1bab1a-9b01-4377-8c3d-0eeac6937086 KO202542 KO202661 0ba02e37-ffbd-4428-ad6f-14cc1de49ef2 6730bf9b-d774-4944-a7f7-bd174d70b121 683e7c7c-af94-4e7d-9174-aa227bde867e]
    forward_shipment.shipment_lines.each do |shipment_line|

      if ignore_orders.include?(forward_shipment.parent_order_id)
        return false
      end

      # next if invalid_shipment.include?(shipment_line.shipment_id)

      is_shipment_done = OrderShipmentData.find_shipments_by_parent_order_code(forward_shipment.parent_order_id)
      unless is_shipment_done.include?(shipment_line.shipment_id)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
      end


      if is_shipment_done.include?(shipment_line.shipment_id)
        barcodes = OrderShipmentData.find_barcodes_by_shipment_and_sku(shipment_line.shipment_id, shipment_line.sku)
        barcodes.concat(OrderShipmentData.find_barcodes_by_shipment_and_sku("#{ shipment_line.shipment_id }-1", shipment_line.sku))
        if barcodes.include?(shipment_line.barcode)
          invalid_shipment << shipment_line.shipment_id
          next if is_shipment_level
          return false
        end
      end

      key = [shipment_line.shipment_id, shipment_line.sku]
      valid_shipments[key] << shipment_line.barcode

    end
    return true unless is_shipment_level
    return false if valid_shipments.empty?

    valid_shipments
  end

  def self.get_valid_barcode_location(shipment_line)
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations
    barcode_location = barcode_locations.find { |bl| bl.location == shipment_line.fulfilment_location }
    barcode_location if barcode_location && barcode_location.quantity == 1
  end

  def self.get_partial_valid_barcodes(shipment_line)
    barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
    return false unless barcode_locations
    barcode_location = barcode_locations.find { |bl| bl.quantity == 1 }
    barcode_location if barcode_location
  end
end
