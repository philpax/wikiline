require 'json'
require 'date'
require 'parallel'
require './common/supported_infoboxes'
require './analysis/wikitext_parser'

def find_template_bounds(text, start_index)
  length = 2
  in_count = 2

  in_comment = false

  while in_count != 0 && (start_index + length < text.size)
    index = start_index + length

    if text[index, 4] == "<!--"
      in_comment = true
      length += 3
    elsif text[index, 3] == "-->"
      in_comment = false
      length += 2
    end

    unless in_comment
      if text[index, 2] == "{{"
        in_count += 2
        length += 1
      elsif text[index, 2] == "}}"
        in_count -= 2 if
        length += 1
      end
    end

    length += 1
  end

  length
end

def segment(entry)
  # Extract the infobox from the text.
  text = entry["text"]
  start_index = text.index(/\{\{[Ii]nfobox/)
  print text if start_index.nil?
  length = find_template_bounds(text, start_index)

  # Extract the infobox.
  infobox = text[start_index, length]

  # Extract the description.
  description = text[start_index+length..-1].strip
  description = description
    .gsub(/<!--.*?-->/, "")
    .gsub(/^\[\[.*?\]\]$/, "")
    .split("\n")
    .map(&:strip)
    .delete_if(&:empty?)
    .join("\n")

  if description.nil?
    description = "No description available."
  else
    while description.start_with?("{{")
      description = description[find_template_bounds(description, 0)..-1]
      description = description[1..-1] unless description.start_with?("{{")

      description = "No description available." if description.nil?
    end
    description = description.split("\n")[0]
    if description.nil?
      puts "warn: missing description for page '#{entry['title']}'"
    else
      description = description[2..-1] if description.start_with? "}}"
    end
  end

  infoboxes = [infobox]
  while true
    start_index = text.index(/\{\{[Ii]nfobox/, start_index + 1)
    break if start_index.nil?

    length = find_template_bounds(text, start_index)
    infobox = text[start_index, length]
    infoboxes.push(infobox)
  end

  {
    "page_title" => entry["title"],
    "infoboxes" => infoboxes,
    "description" => description
  }
end

def extract_infobox(original_infobox)
  parser = WikitextParser.new
  tree = parser.parse(original_infobox)
  infobox = text_print(tree)
  unless infobox.is_a? String
    puts original_infobox
    puts infobox
    raise Exception, 'failed to condense infobox to string'
  end

  # Retrieve the constituent lines of the infobox.
  lines = infobox.split("\n").map(&:strip)
  # Get the type of the infobox.
  type = lines.first["{{infobox ".length..-1]

  # Exclude the infobox starting and ending tags.
  lines = lines[1..-2]

  # Generate our KV map.
  kv = Hash[lines.map { |line|
    index = line.index('=')
    puts JSON.pretty_generate(lines) if index.nil?

    key = line[0..index-1].strip.downcase
    value = line[index+1..-1].strip

    [key, value]
  }]

  if type != nil
    type = type
      .downcase
      .gsub(/\<!--.*?--\>/, "")
      .gsub(/\|.*?$/, "")
      .gsub("/sandbox", "")
      .gsub("milit\u00E4rischer konflikt", "military conflict")
      .strip
  end

  kv["type"] = type
  kv
end

def extract(entry)
  description = entry["description"]

  # Return final output.
  {
    "page_title" => entry["page_title"],
    "description" => entry["description"],
    "events" => entry["infoboxes"].map { |i| extract_infobox(i) }
  }
end

return unless $0 == __FILE__

# Skip these...
SKIP = ["Wikipedia:", "Draft:", "Dominion War", "Command & Conquer", "Template:"]
SKIP_CATEGORIES = ["[[Category:Fictional battles]]"]

puts "analyze: load"
data = JSON.parse(File.read('data/raw-events.json'))
puts "analyze: filtering #{data.length} events"
filtered_data = data.filter { |e|
  !SKIP.any? { |s|
    e["title"].start_with? s
  } && !SKIP_CATEGORIES.any? { |s|
    e["text"].include? s
  }
}

puts "analyze: extract-segmenting #{filtered_data.length} events"
events = Parallel.map(filtered_data) { |e| extract(segment(e)) }

puts "analyze: write #{events.length} events"
File.write('data/semiprocessed-events.json', JSON.generate(events))
puts "analyze: done"
