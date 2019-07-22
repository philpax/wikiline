require 'json'
require 'date'
require 'pg'

puts "dbexprt: load"
data = JSON.parse(File.read('data/processed-events.json'))

puts "dbexprt: clean database"
conn = PG.connect(dbname: "postgres")
conn.exec("DROP DATABASE wikiline")
conn.exec("CREATE DATABASE wikiline")
conn.finish

# TODO: Add _another_ table to split out common elements of Event
puts "dbexprt: initialize database"
conn = PG.connect(dbname: "wikiline")
conn.exec <<-SQL
CREATE TYPE DatePrecision AS ENUM ('era', 'millennium', 'century', 'decade', 'year', 'month', 'day');

CREATE TABLE EventType (
    id SERIAL PRIMARY KEY,
    type TEXT
);

CREATE TABLE Page (
    id SERIAL PRIMARY KEY,
    title TEXT,
    description TEXT
);

CREATE TABLE Event (
    id SERIAL PRIMARY KEY,
    page_id INTEGER REFERENCES Page(id),
    type_id INTEGER REFERENCES EventType(id),
    image TEXT
);

CREATE TABLE EventDate (
    event_id INTEGER REFERENCES Event(id),
    name TEXT,
    date DATE,
    precision DatePrecision
)
SQL

puts "dbexprt: insert types"
types = data.map { |p| p["events"].map { |e| e["type"] } }.flatten.sort.uniq
types_map = Hash[types.map { |t|
    [t, conn.exec_params("INSERT INTO EventType (type) VALUES ($1) RETURNING id", [t])[0]["id"].to_i]
}]

def prepare_date(year, month, day)
    if year <= 0
        date = Date.new(-year + 1, month, day)
        date.iso8601 + " BC"
    else
        date = Date.new(year, month, day)
        date.iso8601
    end
end

data.each_with_index { |p, i|
    puts "dbexprt: insert page #{i}/#{data.length} (#{i*100/data.length}%)" if i % 100 == 0
    page_title = p["page_title"]

    page_id = conn.exec_params(
        "INSERT INTO Page (title, description) VALUES ($1, $2) RETURNING id",
        [page_title, p["description"]]
    )[0]["id"].to_i

    p["events"].each { |e|
        d = e["date"]
        type = types_map[e["type"]]
        image = e["image"]

        event_id = conn.exec_params(
            "INSERT INTO Event (page_id, type_id, image) VALUES ($1::int, $2::int, $3) RETURNING id",
            [page_id, type, image]
        )[0]["id"].to_i

        commands = []

        if d["year1"] != nil
            name = d["year2"].nil? && !d["ongoing"] ? nil : "Start"

            date = prepare_date(d["year1"], d["month1"] || 1, d["day1"] || 1)
            precision = d["precision1"]

            commands.push([event_id, name, date, precision])
        end

        if d["year2"] != nil && !d["ongoing"]
            name = "End"

            date = prepare_date(d["year2"], d["month2"] || 1, d["day2"] || 1)
            precision = d["precision2"]

            commands.push([event_id, name, date, precision])
        end

        commands.each { |params|
            conn.exec_params(
                "INSERT INTO EventDate (event_id, name, date, precision) " +
                "VALUES ($1::int, $2, $3, $4::DatePrecision)",
                params
            )
        }
    }
}
conn.finish
puts "dbexprt: done"