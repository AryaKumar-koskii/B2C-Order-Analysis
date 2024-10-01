# lib/shipments/return_shipment.rb

require 'csv'
require_relative 'shipment_line'
require_relative '../location'
require_relative 'forward_shipment'

class ReturnShipment
  attr_accessor :forward_shipment, :location, :return_order_status, :shipment_lines

  # Class instance variable for looking up return shipments by forward shipment
  @return_shipments_by_forward_shipment = Hash.new { |hash, key| hash[key] = [] }

  class << self
    attr_accessor :return_shipments_by_forward_shipment

    # Class method to read from a CSV file
    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        location_name = row['Fulfillment Location Name'] || row['Fulfilment Location Name']
        location = Location.find_by_full_name(location_name)
        unless location
          puts "Location not found for fulfillment location name: '#{location_name}'"
          next
        end

        # Extract necessary fields
        parent_order_id = row['Channel Parent Order ID'] || row['Channel Parent order ID']
        sku = row['Client SKU ID / EAN']
        barcode = row['External Item Code']

        # If barcode is missing, use data from ForwardShipment
        if barcode
          shipment_id = nil # May need to find the shipment ID using the barcode
        else
          shipment_data = ForwardShipment.find_shipment_data(parent_order_id, sku)
          unless shipment_data && !shipment_data.empty?
            puts "#{parent_order_id}, #{sku}"
            next
          end

          # Assume we take the first matching entry
          barcode = shipment_data.first[:barcode]
          shipment_id = shipment_data.first[:shipment_id]
        end

        # Find the corresponding forward shipment
        forward_shipment = if shipment_id
                             ForwardShipment.find_by_shipment_id(shipment_id)
                           else
                             ForwardShipment.find_by_parent_id(parent_order_id)
                           end

        unless forward_shipment
          puts "Forward shipment not found for Parent Order ID: '#{parent_order_id}'"
          next
        end

        # Check if the SKU and barcode match any line in the forward shipment
        matching_shipment_line = forward_shipment.shipment_lines.find do |line|
          line.sku == sku || (barcode && line.barcode == barcode)
        end

        unless matching_shipment_line
          puts "No matching forward shipment line found for SKU '#{sku}' or barcode '#{barcode}'"
          next
        end

        # Create return shipment
        return_shipment = ReturnShipment.new(
          forward_shipment,
          location,
          row['Return Order Status']
        )

        # Add shipment line
        return_shipment.add_shipment_line(sku, barcode, matching_shipment_line.shipment_id)
      end
    end

    # Return shipments associated with a forward shipment
    def find_by_forward_shipment(forward_shipment)
      self.return_shipments_by_forward_shipment[forward_shipment]
    end

    def all
      self.return_shipments_by_forward_shipment.values.flatten
    end
  end

  def initialize(forward_shipment, location, return_order_status)
    @forward_shipment = forward_shipment
    @location = location
    @return_order_status = return_order_status
    @shipment_lines = [] # Array of ShipmentLine objects

    forward_shipment.add_return_shipment(self)
    self.class.return_shipments_by_forward_shipment[forward_shipment] ||= []
    self.class.return_shipments_by_forward_shipment[forward_shipment] << self
  end

  # Method to add a shipment line (SKU and barcode)
  def add_shipment_line(sku, barcode, shipment_id)
    @shipment_lines << ShipmentLine.new(sku, barcode, shipment_id)
  end
end