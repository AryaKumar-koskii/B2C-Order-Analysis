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

      is_shipment_done = OrderShipmentData.find_by_parent_order_coder_and_shipment_code(forward_shipment.parent_order_id)
      if is_shipment_done.include?(shipment_line.shipment_id)
        invalid_shipment << shipment_line.shipment_id
        next if is_shipment_level
        return false
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

    valid_shipments-invalid_shipment.to_a
  end

  def self.partial_valid_shipment?(forward_shipment, is_shipment_level = false)
    valid_shipments = []
    invalid_shipment = Set.new
    forward_shipment.shipment_lines.each do |shipment_line|

      next if invalid_shipment.include?(shipment_line.shipment_id)

      is_shipment_done = OrderShipmentData.find_by_parent_order_coder_and_shipment_code(forward_shipment.parent_order_id)
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

      forward_shipments = ForwardShipment.find_by_barcode(shipment_line.barcode)
      unless forward_shipments.count > 1
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

    valid_shipments-invalid_shipment.to_a
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

      is_shipment_done = OrderShipmentData.find_by_parent_order_coder_and_shipment_code(forward_shipment.parent_order_id)
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

    valid_shipments-invalid_shipment.to_a
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

      is_shipment_done = OrderShipmentData.find_by_parent_order_coder_and_shipment_code(forward_shipment.parent_order_id)
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

    valid_shipments-invalid_shipment.to_a
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
