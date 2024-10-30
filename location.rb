require 'csv'

class Location
  @locations_by_full_name = {}
  @locations_by_alias = {}
  @location_by_code = {}

  attr_accessor :full_name, :alias, :location_code

  def initialize(full_name, alias_name, location_code)
    @full_name = full_name
    @alias = alias_name
    @location_code = location_code
  end

  # Class method to load location data from the CSV file
  def self.load_locations(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      location = Location.new(row['fulfilment_location'], row['alias'], row['location_code'])

      # Store locations by full name and alias
      @locations_by_full_name[location.full_name] = location
      @locations_by_alias[location.alias] = location
      @location_by_code[location.location_code] = location
    end
  end

  # Static method to lookup location by full name
  def self.find_by_full_name(full_name)
    @locations_by_full_name[full_name]
  end

  # Static method to lookup location by alias, optionally appending "/Stock"
  def self.find_by_alias(alias_name)
    @locations_by_alias[alias_name]
  end
end