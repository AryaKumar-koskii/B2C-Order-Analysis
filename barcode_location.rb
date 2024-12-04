require 'csv'

class BarcodeLocation
  @location_by_barcode = {}

  class << self
    attr_accessor :location_by_barcode

    def find_by_barcode(barcode)
      if barcode
        @location_by_barcode[barcode.upcase]
      end
    end

    def all
      @location_by_barcode
    end

    def find_barcodes_with_invalid_quantities
      self.location_by_barcode.values.flatten.select do |barcode_location|
        barcode_location.quantity > 1 || barcode_location.quantity < 0
      end
    end
  end

  attr_accessor :location, :barcode, :product, :quantity

  def initialize(location, barcode, product, quantity)
    @location = location
    @barcode = barcode ? barcode.upcase : barcode
    @product = product
    @quantity = quantity
  end

  # Class method to load barcode location data from barcode_location.csv
  def self.read_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      location_with_stock = row['Location']

      if ['Physical Locations/Inter-warehouse transit'].include?(location_with_stock)
        next
      end
      location_alias = location_with_stock.gsub('/Stock', '') # Remove "/Stock"

      location = Location.find_by_alias(location_alias)
      raise "Location alias not found for: '#{row['Location']}'" unless location

      barcode_location = BarcodeLocation.new(
        location.full_name,
        row['Lot/Serial Number'].upcase,
        parse_product(row['Product']),
        row['Quantity'].to_i
      )

      self.location_by_barcode[barcode_location.barcode] ||= []
      self.location_by_barcode[barcode_location.barcode] << barcode_location
    end
  end

  private

  def self.parse_product(product_string)
    # This regex captures the part after the brackets
    match = product_string.match(/\[(.*?)\]\s*(.*)/)
    match ? match[2] : product_string
  end
end