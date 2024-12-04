require 'csv'
require_relative 'shipment_line'
require_relative '../location'
require_relative '../pending_forward'

class ForwardShipment
  attr_accessor :location, :forward_order_id, :parent_order_id, :shipment_lines, :shipment_id, :return_shipments, :pending

  # Class instance variables for quick lookup
  @forward_shipments_by_parent_id = {}
  @forward_shipments_by_barcode = Hash.new { |hash, key| hash[key] = [] }
  @forward_shipments_by_sku = Hash.new { |hash, key| hash[key] = [] }
  @forward_shipments_without_returns = []
  @forward_shipments_by_shipment_id = {}
  @forward_shipments_with_returns = {}
  @shipment_data_by_parent_order_id_and_sku = {}

  class << self
    attr_accessor :forward_shipments_by_parent_id, :forward_shipments_by_barcode,
                  :forward_shipments_by_sku, :forward_shipments_without_returns,
                  :forward_shipments_by_shipment_id, :forward_shipments_with_returns,
                  :shipment_data_by_parent_order_id_and_sku

    # Class method to read from a CSV file, considering only pending orders
    def read_from_csv(file_path)
      CSV.foreach(file_path, headers: true) do |row|
        forward_order_id = row['Parent Order ID']
        parent_order_id = row['Parent Order ID']

        # Only process if the forward order is pending
        next unless PendingForward.pending?(forward_order_id)

        if forward_order_id == 'KO228986'
          true
        end

        location_name = row['Fulfilment Location Name'] || row['Fulfillment Location Name']
        location = Location.find_by_full_name(location_name)
        unless location
          puts "Location not found for fulfillment location name: '#{location_name}'"
          next
        end

        # Create or retrieve the existing forward shipment
        shipment_id = row['Shipment ID'].to_s
        forward_order = self.forward_shipments_by_parent_id[parent_order_id]
       if shipment_id == '202345' or parent_order_id == '2572038a-f443-4bdc-bbbc-c2ac0c509636'
         p shipment_id
       end
        unless forward_order
          forward_order = ForwardShipment.new(location, forward_order_id,
                                                 parent_order_id,
                                                 shipment_id,
                                                 true)
        end

        # Add shipment line
        forward_order.add_shipment_line(row['Fulfilment Location Name'], row['Client SKU ID / EAN'], row['External Item Code'], shipment_id)

        # Store data for lookup by parent_order_id and SKU``
        key = [parent_order_id, row['Client SKU ID / EAN']]
        self.shipment_data_by_parent_order_id_and_sku[key] ||= []
        self.shipment_data_by_parent_order_id_and_sku[key] << { barcode: row['External Item Code'], shipment_id: shipment_id }
      end
    end

    def find_forward_shipments_with_multiple_shipments
      multiple_shipment_orders = []

      # Group shipments by parent_order_id and count the number of shipment_ids
      forward_shipments_by_parent_id.each do |parent_order_id, forward_shipment|
        matching_shipments = forward_shipments_by_shipment_id.values.select do |shipment|
          shipment.parent_order_id == parent_order_id
        end

        # Check if the parent_order_id is associated with more than one shipment_id
        if matching_shipments.size > 1
          multiple_shipment_orders << forward_shipment
        end
      end

      multiple_shipment_orders
    end

    def find_by_shipment_id(shipment_id)
      @forward_shipments_by_shipment_id[shipment_id]
    end

    def find_by_barcode(barcode)
      @forward_shipments_by_barcode[barcode]
    end

    def find_by_sku(sku)
      @forward_shipments_by_sku[sku]
    end

    def find_without_return_shipments
      @forward_shipments_without_returns
    end

    def find_by_parent_id(parent_id)
      @forward_shipments_by_parent_id[parent_id]
    end

    def find_with_return_shipments
      @forward_shipments_with_returns
    end

    def all
      @forward_shipments_by_parent_id.values
    end

    def find_barcodes_in_multiple_shipments
      @forward_shipments_by_barcode.select do |barcode, shipments|
        shipments.size > 1
      end
    end

    # Method to find shipment data by parent order ID and SKU
    def find_shipment_data(parent_order_id, sku)
      key = [parent_order_id, sku]
      self.shipment_data_by_parent_order_id_and_sku[key]
    end
  end

  def initialize(location, forward_order_id, parent_order_id, shipment_id, pending = false)
    @location = location
    @forward_order_id = forward_order_id
    @parent_order_id = parent_order_id
    @shipment_id = shipment_id
    @shipment_lines = [] # Array of ShipmentLine objects
    @return_shipments = [] # Array of associated ReturnShipments
    @pending = pending

    # Populate class instance variables
    self.class.forward_shipments_by_parent_id[@parent_order_id] = self
    self.class.forward_shipments_by_shipment_id[@shipment_id] = self
    self.class.forward_shipments_without_returns << self unless @return_shipments.any?
  end

  def barcodes_in_same_location?
    self.shipment_lines.all? do |shipment_line|
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      barcode_locations && barcode_locations.any? do |barcode_location|
        barcode_location.location == self.location.alias
      end
    end
  end

  def barcodes_in_other_locations?
    self.shipment_lines.any? do |shipment_line|
      barcode_locations = BarcodeLocation.find_by_barcode(shipment_line.barcode)
      barcode_locations && barcode_locations.any? do |barcode_location|
        barcode_location.location != self.location.alias
      end
    end
  end

  def barcode_returned?(barcode)
    self.return_shipments.any? do |return_shipment|
      return_shipment.shipment_lines.any? { |line| line.barcode == barcode }
    end
  end

  # Method to add a shipment line (SKU and barcode)
  def  add_shipment_line(fulfilment_location, sku, barcode, shipment_id)
    # Check for duplicate barcode in the same shipment
    if @shipment_lines.any? { |line| line.barcode == barcode }
      puts "Duplicate barcode '#{barcode}' in forward shipment '#{@forward_order_id}'."
      return
    end
    @shipment_lines << ShipmentLine.new(fulfilment_location, sku, barcode, shipment_id)

    # Indexing for queries
    self.class.forward_shipments_by_barcode[barcode] << self
    self.class.forward_shipments_by_sku[sku] << self
  end

  def add_return_shipment(return_shipment)
    @return_shipments << return_shipment
    self.class.forward_shipments_without_returns.delete(self)
    self.class.forward_shipments_with_returns[@shipment_id] = self
  end
end