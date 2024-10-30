# frozen_string_literal: true
require_relative 'read_sto_file'
require_relative '../../config'
require_relative '../location'
require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'date'

def send_api_request(payload)
  uri = URI.parse('http://localhost:8069/b2b_order/create') # Replace with your actual API endpoint

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = false # Use SSL/TLS if required

  request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json', 'odoo_token' => ODOO_TOKEN })
  request.body = payload.to_json

  begin
    response = http.request(request)
    puts "Response Code: #{response.code}"
    puts "Response Body: #{response.body}"
  rescue StandardError => e
    puts "An error occurred during the API request: #{e.message}"
    nil
  end

  response
end

def construct_payload(from_loc, to_loc, sto_records)
  order_items = sto_records.each_with_index.map do |sto_record, index|
    {
      "order_item_code": "SO_#{Date.today}-STO_#{index + 1}",
      "channel_sku_code": sto_record.sku,
      "quantity": sto_record.quantity
    }
  end

  {
    "jsonrpc": "2.0",
    "params": {
      "args": {
        "location_code": from_loc.location_code.to_i,
        "partner_code": to_loc.location_code.to_i,
        "order_code": "SO_#{Time.now.to_datetime}_#{from_loc.location_code.to_i}_#{to_loc.location_code.to_i}-STO",
        "order_time": Time.now.to_date,
        "qc_status": "PASS",
        "currency": "INR",
        "order_items": order_items
      }
    }
  }
end

def load_file
  p 'loading location_mapping file'
  Location.load_locations('../csv_files/location_alias_mapping.csv')

  p 'loading file to create STO'
  ReadSTOFile.read_from_csv('../results/partial_availability_orders.csv')
end

def main
  begin
    load_file

    ReadSTOFile.sto_records_by_from_to.each do |(from_loc, to_loc), sto_records|
      if from_loc != to_loc
        payload = construct_payload(Location.find_by_full_name(from_loc), Location.find_by_full_name(to_loc), sto_records)
        puts "Sending payload for from_loc: #{from_loc}, to_loc: #{to_loc}"
        response = send_api_request(payload)
        # Handle the response as needed
        if response.code.to_i == 200
          puts 'Request was successful.'
        else
          puts 'Request failed.'
        end
      end
    end

    puts 'All API requests have been processed.'
  rescue => e
    puts "An error occurred: #{e.message}"
  end
end

# Run the main method
main