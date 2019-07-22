require 'json'
require 'date'

data = JSON.parse(File.read('data/processed-events.json'))

events = []
data.each { |p|
    p["events"].each { |e|
        d = e["date"]
        begin
            if d["year1"] != nil
                title = d["year2"].nil? ? p["page_title"] : "Start of #{p["page_title"]}"

                events.push({
                    title: title,
                    date: Date.new(d["year1"], d["month1"] || 1, d["day1"] || 1),
                    precision: d["precision1"]
                })
            end

            if d["year2"] != nil && !d["ongoing"]
                title = d["year1"].nil? ? p["page_title"] : "End of #{p["page_title"]}"

                events.push({
                    title: title,
                    date: Date.new(d["year2"], d["month2"] || 1, d["day2"] || 1),
                    precision: d["precision2"]
                })
            end
        rescue Exception => exc
            puts(e)
            puts("#{d["year1"]}, #{d["month1"] || 1}, #{d["day1"] || 1}")

            raise
        end
    }
}

events.sort! { |a, b| a[:date] <=> b[:date] }
events.each { |e| puts "#{e[:date].iso8601}: #{e[:title]} (precision: #{e[:precision]})" }
