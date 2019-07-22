require 'nokogiri'
require 'json'
require './common/supported_infoboxes'

FILENAME = 'data/raw-events.json'

class Parser < Nokogiri::XML::SAX::Document
  def start_element(name, attrs = [])
    if name == "mediawiki"
      @count = 0
      @events = []
    elsif name == "page"
      @title = ""
      @text = ""
    else
      @parsing_title = true if name == 'title'
      @parsing_text = true if name == 'text'
    end
  end

  def characters(string)
    @title += string if @parsing_title
    @text += string if @parsing_text
  end

  def end_element(name)
    @parsing_title = false if name == 'title'
    @parsing_text = false if name == 'text'

    if name == "page"
      dtext = @text.downcase
      INFOBOXES.each { |ib|
        next unless dtext.include? "{{infobox #{ib}"

        @count += 1
        # puts "#{@count} #{ib}: #{@title}"

        @events.push({
          title: @title,
          text: @text
        })

        if @count % [(@count/4), 1].max == 0
          File.write(FILENAME, JSON.generate(@events))
          puts "dump: partial write at #{@count}"
        end
      }
    elsif name == "mediawiki"
      File.write(FILENAME, JSON.generate(@events))
    end
  end
end

puts "dump: start"
Nokogiri::XML::SAX::Parser.new(Parser.new).parse(File.open('data/enwiki-latest-pages-articles-multistream.xml'))
puts "dump: end"
