class BarcodeLocation
  @barcodes_by_location = {}

  def initialize(location, barcode, product, quantity)
    @location = location
    @barcode = barcode
    @product = product
    @quantity = quantity
  end

  # Class method to load barcode location data from barcode_location.csv
  def self.read_from_csv(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      location_alias = row['Location'].gsub('/Stock', '')  # Remove /Stock

      location = Location.find_by_alias(location_alias)
      raise "Location alias not found for: '#{row['Location']}'" unless location

      barcode_location = BarcodeLocation.new(
        location.full_name,
        row['Lot/Serial Number'],
        row['Product'],
        row['Quantity']
      )

      @barcodes_by_location[barcode_location.barcode] ||= []
      @barcodes_by_location[barcode_location.barcode] << barcode_location
    end
  end

  def self.find_by_barcode(barcode)
    @barcodes_by_location[barcode]
  end
end