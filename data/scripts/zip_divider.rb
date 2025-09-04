#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'zip'
require 'fileutils'

class ZipDivider
  def initialize(zip_file_path, approx_size_mb, max_files_per_zip)
    @zip_file_path = zip_file_path
    @approx_size_bytes = approx_size_mb * 1024 * 1024
    @max_files_per_zip = max_files_per_zip
    @output_directory = File.dirname(@zip_file_path)
  end

  def run
    start_time = Time.now

    validate_zip_file!
    puts 'Processing ZIP file...'

    divide_zip_file

    end_time = Time.now
    total_time = end_time - start_time

    puts 'Process completed successfully!'
    puts "Total processing time: #{total_time.round(2)} seconds"
  end

  private

  def validate_zip_file!
    raise ArgumentError, "ZIP file not found: #{@zip_file_path}" unless File.exist?(@zip_file_path)

    unless File.extname(@zip_file_path).casecmp('.zip').zero?
      raise ArgumentError, "File must be a ZIP file: #{@zip_file_path}"
    end

    File.open(@zip_file_path, 'rb') do |file|
      magic = file.read(4)
      unless ["PK\x03\x04", "PK\x05\x06", "PK\x07\x08"].include?(magic)
        raise ArgumentError, 'Invalid ZIP file: not a valid ZIP archive'
      end
    end

    puts '✓ ZIP file validation passed'
  end

  def divide_zip_file
    current_batch = []
    current_size = 0
    batch_number = 0
    total_files = 0

    Zip::File.open(@zip_file_path) do |zip_file|
      entries = zip_file.entries.select(&:file?)
      total_files = entries.length
      puts "Found #{total_files} files"

      entries.each_with_index do |entry, index|
        entry_size = entry.size

        # Check if we need to create a batch
        if current_batch.length >= @max_files_per_zip ||
           (current_batch.any? && current_size + entry_size > @approx_size_bytes)

          batch_number += 1
          create_zip_batch(current_batch, batch_number)

          current_batch = [entry]
          current_size = entry_size
        else
          current_batch << entry
          current_size += entry_size
        end

        show_progress(index + 1, total_files, batch_number)
      end

      if current_batch.any?
        batch_number += 1
        create_zip_batch(current_batch, batch_number)
      end
    end

    # Clear progress lines and show final summary
    print "\r\033[K\033[A\033[K"
    puts "\nDivision Summary:"
    puts "Total files processed: #{total_files}"
    puts "Total ZIP files created: #{batch_number}"
  end

  def create_zip_batch(batch, batch_number)
    zip_filename = "#{generate_zip_name(batch_number)}.zip"
    zip_path = File.join(@output_directory, zip_filename)

    Zip::OutputStream.open(zip_path) do |zos|
      batch.each do |entry|
        zos.put_next_entry(entry.name)
        zos.write(entry.get_input_stream.read)
      end
    end
  end

  def generate_zip_name(number)
    # Character sequence: 0-9, a-z, A-Z (total: 62 characters)
    chars = ('0'..'9').to_a + ('a'..'z').to_a + ('A'..'Z').to_a
    base = chars.length

    # Convert number to base-62 and pad to 12 characters
    result = ''
    n = number - 1 # Convert to 0-based indexing

    if n.zero?
      result = '0'
    else
      while n.positive?
        result = chars[n % base] + result
        n /= base
      end
    end

    # Pad with leading zeros to make 12 characters
    padded_result = result.rjust(12, '0')

    # Add hyphens every 3 characters: "000-000-000-000"
    padded_result.scan(/.{1,3}/).join('-')
  end

  def show_progress(current, total, batch_count)
    percentage = (current.to_f / total * 100).round(1)
    progress_width = 50
    filled_width = (percentage / 100 * progress_width).to_i

    progress_bar = '#' * filled_width + '-' * (progress_width - filled_width)

    print "\r[#{progress_bar}] #{percentage}%"
    print "\n#{current}/#{total} files processed, #{batch_count} ZIPs created\r\033[A"
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

def get_approx_size_input
  loop do
    print 'Digite o tamanho aproximado de cada ZIP (em MB): '
    input = gets.chomp.strip

    if input.empty?
      puts 'Este campo é obrigatório. Por favor, tente novamente.'
      next
    end

    begin
      size = Float(input)
      if size <= 0
        puts 'O tamanho deve ser maior que 0. Por favor, tente novamente.'
        next
      end
      return size
    rescue ArgumentError
      puts 'Por favor, digite um número válido.'
    end
  end
end

def get_max_files_input
  loop do
    print 'Digite o máximo de arquivos por ZIP: '
    input = gets.chomp.strip

    if input.empty?
      puts 'Este campo é obrigatório. Por favor, tente novamente.'
      next
    end

    begin
      count = Integer(input)
      if count <= 0
        puts 'O número deve ser maior que 0. Por favor, tente novamente.'
        next
      end
      return count
    rescue ArgumentError
      puts 'Por favor, digite um número inteiro válido.'
    end
  end
end

# Check if running in compilation mode (ocran)
if defined?(Ocran) || ARGV.include?('--compile-mode')
  puts 'Running in compilation mode - skipping execution'
  exit 0
end

puts '=== ZIP Divider ==='
puts 'Este script divide um arquivo ZIP grande em arquivos menores.'
puts ''

puts '=== Diretório atual ==='
puts Dir.pwd
puts ''

zip_file_path = get_user_input('Digite o caminho para o arquivo ZIP')
approx_size_mb = get_approx_size_input
max_files_per_zip = get_max_files_input

puts ''
puts 'Configuração:'
puts "Arquivo ZIP: #{zip_file_path}"
puts "Tamanho aproximado por ZIP: #{approx_size_mb} MB"
puts "Máximo de arquivos por ZIP: #{max_files_per_zip}"
puts "Diretório de saída: #{File.dirname(zip_file_path)}"
puts ''

print 'Deseja continuar? (s/N): '
confirmation = gets.chomp.strip.downcase

unless %w[s sim y yes].include?(confirmation)
  puts 'Operação cancelada.'
  exit 0
end

puts ''

begin
  divider = ZipDivider.new(zip_file_path, approx_size_mb, max_files_per_zip)
  divider.run
rescue StandardError => e
  puts "Error: #{e.message}"
  pp e.backtrace
  exit 1
end
