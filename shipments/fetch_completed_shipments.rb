require_relative '../../config'
require_relative '../const'
require 'net/http'
require 'json'
require 'csv'
require 'uri'

class FetchCompletedShipments

  def self.write_into_csv(completed_shipments)
    return if completed_shipments.nil? || completed_shipments.empty?

    # Parse JSON data into Ruby hash
    parsed_data = JSON.parse(completed_shipments)

    # Extract the `data` array from the response
    shipment_data = parsed_data['data'] || []

    # Write to CSV
    CSV.open("#{Const::PROJECT_ROOT}/csv_files/support_data/completed_shipments.csv", 'w') do |csv|
      # Add headers
      csv << %w[external_parent_order_code external_shipment_id state]

      # Write each shipment data
      shipment_data.each do |shipment|
        csv << [
          shipment['external_parent_order_code'],
          shipment['external_shipment_id'],
          shipment['state']
        ]
      end
    end

    puts "Completed shipments written to 'completed_shipments.csv'."
  end

  def self.fetch_completed_shipments
    uri = URI.parse(ODOO_PROD_SHIPMENTS)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true # True if https

    payload = {
      "get_ko_data": false,
      "get_last_move_data": false,
      "get_completed_pickings": true,
      "barcodes": []
    }

    formatted_payload = JSON.dump(payload)
    request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json', 'odoo_token' => ODOO_TOKEN })
    request.body = "\"#{formatted_payload.gsub('"', '\\"')}\""

    begin
      response = http.request(request)
      puts "Response Code: #{response.code}"

      if response.code == '200'
        completed_shipments = response.body
        write_into_csv(completed_shipments)
      else
        puts "Failed to fetch completed shipments. Response: #{response.body}"
      end
    rescue StandardError => e
      puts "An error occurred during the API request: #{e.message}"
    end

  end
end
