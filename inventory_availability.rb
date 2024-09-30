require 'csv'

class InventoryAvailability
  attr_accessor :location, :barcode, :product, :quantity

  def initialize(location, barcode, product, quantity)
    @location = location # This is now a Location object
    @barcode = barcode # Lot/Serial Number mapped to barcode
    @product = parse_product(product) # Parse product to extract the meaningful part
    @quantity = quantity
  end

  def read_inventory_availability(file_path)
    inventory_availability_list = []

    CSV.foreach(file_path, headers: true) do |row|
      location = Location.new(
        row['Company/External Company ID'], # External Company ID
        row['Company'],                     # Company Name
        row['Location']                     # Location Name
      )

      inventory_availability = InventoryAvailability.new(
        location,          # Location object
        row['Lot/Serial Number'],  # Barcode
        row['Product'],            # Product (parse product name if necessary)
        row['Quantity']            # Quantity
      )

      inventory_availability_list << inventory_availability
    end

    inventory_availability_list
  end

  private
  # check this part
  def parse_product(product_string)
    # This regex captures the part after the brackets
    match = product_string.match(/\[(.*?)\]\s*(.*)/)
    match ? match[2] : product_string # Return the second part if the pattern matches
  end
end