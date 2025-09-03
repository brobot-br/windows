#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'zip'
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'tempfile'

class ZipSplitter
  MAX_FILES_PER_ZIP = 500
  MAX_SIZE_PER_ZIP = 1 * 1024 * 1024 # 1.megabyte
  REQUEST_INTERVAL = 0.5

  def initialize(token, zip_file_path, env)
    @token = token
    @zip_file_path = zip_file_path
    @base_url = build_base_url(env)[env] || build_base_url(env)['development']
    @temp_files = []

    # Ensure cleanup happens even if script exits unexpectedly
    at_exit { cleanup }
  end

  def run
    validate_token!
    validate_zip_file!

    puts 'Processing ZIP file in streaming mode...'

    stream_process_zip_file

    cleanup
    puts 'Process completed successfully!'
  end

  private

  def build_base_url(_env)
    {
      'production' => 'https://api.platform.brobot.com.br',
      'staging' => 'https://api.platform-staging.brobot.com.br',
      'development' => 'http://localhost:3000'
    }
  end

  def validate_zip_file!
    raise ArgumentError, "ZIP file not found: #{@zip_file_path}" unless File.exist?(@zip_file_path)

    unless File.extname(@zip_file_path).casecmp('.zip').zero?
      raise ArgumentError,
            "File must be a ZIP file: #{@zip_file_path}"
    end

    # Fast validation using magic bytes - much faster than opening the entire archive
    File.open(@zip_file_path, 'rb') do |file|
      magic = file.read(4)
      unless ["PK\x03\x04", "PK\x05\x06", "PK\x07\x08"].include?(magic)
        raise ArgumentError, 'Invalid ZIP file: not a valid ZIP archive'
      end
    end

    puts '✓ ZIP file validation passed'
  end

  def validate_token!
    uri = URI("#{@base_url}/api/v2/dfe/fiscal_documents?per_page=1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Get.new(uri)
    request['token'] = @token
    # request['Content-Type'] = 'application/json'

    response = http.request(request)

    raise ArgumentError, "Invalid token or API error: #{response.code} - #{response.body}" unless response.code == '200'

    puts '✓ Token validation passed'
  end

  def stream_process_zip_file
    current_batch = []
    current_size = 0
    batch_number = 0
    total_files = 0
    successful_uploads = 0
    failed_uploads = 0

    Zip::File.open(@zip_file_path) do |zip_file|
      # Count total XML files first for progress tracking
      xml_entries = zip_file.entries.select { |entry| entry.file? && entry.name.downcase.end_with?('.xml') }
      total_files = xml_entries.length
      puts "Found #{total_files} XML files"

      xml_entries.each_with_index do |entry, index|
        # Create temporary file for this XML
        basename = File.basename(entry.name, '.xml')
        temp_file = Tempfile.new([basename, '.xml'])
        temp_file.binmode

        # Extract entry content to temp file
        temp_file.write(entry.get_input_stream.read)
        temp_file.close

        @temp_files << temp_file

        xml_file = {
          name: File.basename(entry.name),
          path: temp_file.path,
          size: File.size(temp_file.path)
        }

        # Check if we need to create a batch
        if current_batch.length >= MAX_FILES_PER_ZIP ||
           (current_size + xml_file[:size] > MAX_SIZE_PER_ZIP && current_batch.any?)

          # Create and upload current batch
          batch_number += 1
          upload_result = create_and_upload_batch(current_batch, batch_number, total_files)

          if upload_result
            successful_uploads += 1
          else
            failed_uploads += 1
          end

          # Start new batch
          current_batch = [xml_file]
          current_size = xml_file[:size]
        else
          current_batch << xml_file
          current_size += xml_file[:size]
        end

        # Show progress
        puts "Processed #{index + 1}/#{total_files} files..." if ((index + 1) % 50).zero?
      end

      # Process remaining files in final batch
      if current_batch.any?
        batch_number += 1
        upload_result = create_and_upload_batch(current_batch, batch_number, total_files)

        if upload_result
          successful_uploads += 1
        else
          failed_uploads += 1
        end
      end
    end

    puts "\nStreaming Process Summary:"
    puts "Total XML files processed: #{total_files}"
    puts "Successful uploads: #{successful_uploads}"
    puts "Failed uploads: #{failed_uploads}"
  end

  def create_and_upload_batch(batch, batch_number, _total_batches_estimate)
    zip_filename = "batch_#{batch_number.to_s.rjust(3, '0')}.zip"
    zip_temp_file = Tempfile.new([zip_filename.gsub('.zip', ''), '.zip'])
    zip_temp_file.close

    @temp_files << zip_temp_file

    # Create the ZIP batch
    Zip::OutputStream.open(zip_temp_file.path) do |zos|
      batch.each do |xml_file|
        zos.put_next_entry(xml_file[:name])
        zos.puts(File.read(xml_file[:path]))
      end
    end

    zip_batch = {
      path: zip_temp_file.path,
      filename: zip_filename,
      file_count: batch.length,
      size: File.size(zip_temp_file.path)
    }

    # Upload immediately
    puts "Uploading #{zip_batch[:filename]} (batch #{batch_number}) - #{zip_batch[:file_count]} files, #{format_size(zip_batch[:size])}"

    begin
      upload_zip_file(zip_batch)
      puts "✓ Successfully uploaded #{zip_batch[:filename]}"

      # Clean up the zip file immediately after successful upload to save disk space
      cleanup_temp_file(zip_temp_file)

      true
    rescue StandardError => e
      puts "✗ Failed to upload #{zip_batch[:filename]}: #{e.message}"
      false
    ensure
      # Add a small delay between uploads
      sleep(REQUEST_INTERVAL)
    end
  end

  def cleanup_temp_file(temp_file)
    temp_file.close unless temp_file.closed?
    temp_file.unlink if temp_file.respond_to?(:unlink)
    @temp_files.delete(temp_file)
  rescue StandardError => e
    puts "Warning: Could not cleanup temp file #{temp_file.path}: #{e.message}"
  end

  def upload_zip_file(zip_batch)
    uri = URI("#{@base_url}/api/v2/archives")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    # Use File.open with block to ensure file handle is closed properly
    File.open(zip_batch[:path], 'rb') do |file|
      form_data = [
        ['archive', file, { filename: zip_batch[:filename] }]
      ]

      request = Net::HTTP::Post.new(uri)
      request['token'] = @token
      request.set_form(form_data, 'multipart/form-data')

      response = http.request(request)

      raise "HTTP #{response.code}: #{response.body}" unless response.code.to_i.between?(200, 299)

      response
    end
  end

  def cleanup
    @temp_files.each do |temp_file|
      # Close the file first to release handle on Windows
      temp_file.close unless temp_file.closed?

      # On Windows, we need to be more careful with file deletion
      temp_file.unlink if temp_file.respond_to?(:unlink)
    rescue StandardError => e
      # Log error but don't fail the entire process
      puts "Warning: Could not cleanup temp file #{temp_file.path}: #{e.message}"
    end
    @temp_files.clear
  end

  def format_size(size)
    if size < 1024
      "#{size} bytes"
    elsif size < 1024 * 1024
      "#{(size / 1024.0).round(1)} KB"
    else
      "#{(size / (1024.0 * 1024)).round(1)} MB"
    end
  end
end

# Script execution
def get_user_input(prompt, required: true)
  loop do
    print "#{prompt}: "
    input = gets.chomp.strip

    if required && input.empty?
      puts 'Este campo é obrigatório. Por favor, tente novamente.'
      next
    end

    return input
  end
end

def get_environment_choice
  puts "\nEscolha o ambiente:"
  puts '1. Development (localhost:3000)'
  puts '2. Staging'
  puts '3. Production'

  loop do
    print 'Digite o número do ambiente (1-3): '
    choice = gets.chomp.strip

    case choice
    when '1'
      return 'development'
    when '2'
      return 'staging'
    when '3'
      return 'production'
    else
      puts 'Opção inválida. Por favor, digite 1, 2 ou 3.'
    end
  end
end

# Check if running in compilation mode (ocran)
if defined?(Ocran) || ARGV.include?('--compile-mode')
  puts 'Running in compilation mode - skipping execution'
  exit 0
end

puts '=== ZIP Splitter ==='
puts 'Este script divide arquivos ZIP grandes em arquivos menores e os envia para a API.'
puts ''

# show current directory
puts '=== Diretório atual ==='
puts Dir.pwd
puts ''

token = get_user_input('Digite o token da API')
zip_file_path = get_user_input('Digite o caminho para o arquivo ZIP')
env = get_environment_choice

puts ''
puts 'Configuração:'
puts "Token: #{token[0..10]}..." if token.length > 10
puts "Arquivo ZIP: #{zip_file_path}"
puts "Ambiente: #{env}"
puts ''

print 'Deseja continuar? (s/N): '
confirmation = gets.chomp.strip.downcase

unless %w[s sim y yes].include?(confirmation)
  puts 'Operação cancelada.'
  exit 0
end

puts ''

begin
  splitter = ZipSplitter.new(token, zip_file_path, env)
  splitter.run
rescue StandardError => e
  puts "Error: #{e.message}"
  pp e.backtrace
  exit 1
end
