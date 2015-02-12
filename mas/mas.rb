require "csv"
require 'yaml'
require 'date'

if ARGV[0]
  config = YAML.load_file(ARGV[0])
else
  config = YAML.load_file('config.yml')
end

class Parser
  def initialize(definitions)
    @definitions = definitions
  end

  def run(header_string)
    header = {}

    @definitions[:rules].each do |definition|
      header[definition[:name]] = cut(definition[:cut], header_string, definition[:filter])
    end

    header
  end

  def cut(cuts, text, filter)
    values = ""
    cuts.each do |cut|
      values << text[(cut[0] - 1)..(cut[1] - 1)]
    end
    apply_filter(values, filter)
  end

  def apply_filter(string, filter)
    if filter
      Filters.new.send(filter, string)
    else
      string
    end
  end
end

class Filters
  def int(string)
    string.to_i
  end
  def float(string)
    string.to_f / 100
  end
  def date_join(string)
    text = ""
    date = string[0..5].split("/")
    text << "20#{string[6..7]}"
    text << "-"
    text << date[1]
    text << "-"
    text << date[0]
    text << " "
    text << "#{string[8..12]}:00"
    text
  end

  def clear(string)
    string.gsub!( "/", "")
    string.gsub!(" ", "")
    string.gsub!(":", "")
    string
  end

  def change_value(string)
    if string == '16'
      false
    else
      true
    end
  end
end

class Creator
  def initialize(definitions, input_file)
    @definitions = definitions
    @input_file = input_file
  end

  def create_csv()
    f = File.open(@input_file, "r")
    tickets = []
    lines = []
    last_id = 0
    order = 1
    f.each_line do |line|
      type = line_type(line)
      definition = @definitions.select { |defin| defin[:type] == type }.first
      line_parsed = Parser.new(definition).run(line)

      # unless ["80", "81"].include? line[20..22]
      #   csv << @definitions[:rules].map{ |w| line_parsed[w[:name]] }
      # end

      if type == :ticket
        last_id = line_parsed[:code]
        tickets << CSV.generate_line(line_parsed.values, { col_sep: ';' })
        order = 1
      else
        line_parsed[:activity_code] = last_id
        line_parsed[:order] = order
        # if quantity or weight are negatives put the total in negative if it
        # isn't yet
        if (line_parsed[:weight] < 0 || line_parsed[:quantity] < 0) && line_parsed[:total] > 0
          line_parsed[:total] = 0 - line_parsed[:total]
        end
        line_parsed[:activity_code] = last_id
        lines << CSV.generate_line(line_parsed.values, { col_sep: ';' })
        order += 1
      end

    end

    f.close

    { tickets: tickets, lines: lines }
  end

  def line_type(line)
    if line[0] == 'L'
      :line
    else
      :ticket
    end
  end
end


definitions = [
  {
    type: :ticket,
    rules:
    [
      {
        cut:[[1,2]],
        name: :location_code,
        filter: :int
      }, {
        cut:[[42,49]],
        name: :total,
        filter: :float
      }, {
        cut:[[29,41]],
        name: :creation_date,
        filter: :date_join
      },
      {
        cut:[[13,15]],
        name: :staff_code,
      },
      {
        cut: [[29, 30], [32, 33], [35, 36], [1, 2], [4, 8], [42, 49]], # fecha ddmmaa location_code ticket_number total
        name: :code,
        filter: :clear
      },
      {
        cut:[[24,28]],
        name: :customer_code
      },
      {
        cut: [[50,50]],
        name: :custom1,
        filter: :int # tipo de pago
      },
      {
        cut: [[21, 22]],
        name: :returned,
        filter: :change_value
      }
    ]
  },
  {
    type: :line,
    rules: [
      {
        cut: [[1, 2]],
        name: :order
      },
      {
        cut: [[81, 93], [4,8], [2,3], [14,15]],
        name: :activity_code,
        filter: :clear
      }, {
        cut: [[50, 55]],
        name: :product_code
      },
      {
        cut: [[19,25]],
        name: :weight,
        filter: :int
      },
      {
        cut: [[26,32]],
        name: :quantity,
        filter: :int
      },
      {
        cut: [[33, 40]],
        name: :price,
        filter: :float
      },
      {
        cut: [[41, 48]],
        name: :total,
        filter: :float
      },
      {
        cut: [[56, 80]],
        name: :description
      }
    ]
  }
]

if Dir.glob(config["input_folder"] + "*").size > 0
  timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
  tickets_file = File.open("#{config["output_folder_tickets"]}all_ticket_#{timestamp}.csv", "wb")
  lines_file = File.open("#{config["output_folder_lines"]}all_line_#{timestamp}.csv", "wb")
  
  tickets_file << CSV.generate_line(definitions.select { |definition| definition[:type] == :ticket }.first[:rules].map { |rule| rule[:name] }, { col_sep: ';' })
  lines_file << CSV.generate_line(definitions.select { |definition| definition[:type] == :line }.first[:rules].map { |rule| rule[:name] }, { col_sep: ';' })
  
  Dir.foreach(config["input_folder"]) do |item|
    if item.split(".")[1] == "DAT" || item.split(".")[1] == "dat"
  
      output = Creator.new(definitions, "#{config["input_folder"]}#{item}").create_csv
  
      tickets_file << output[:tickets].join
      lines_file << output[:lines].join
  
      File.delete("#{config["input_folder"]}#{item}")
  
    end
  end
  tickets_file.close
  lines_file.close
  
  puts 'done'
else
  puts 'no files'
end
