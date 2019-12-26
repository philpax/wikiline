# coding: utf-8
require 'json'
require 'date'
require 'parallel'

DEBUG_PARSE = false unless defined? DEBUG_PARSE

def parse_age_ymwd(tag, ongoing)
  # Extract k-v components.
  components =
    tag[2..-3]
      .split("|")[1..]
      .map { |kv| kv.split("=").map(&:strip) }

  # If we only have two components, assume this is in the format {{tag|yyyy-mm-dd|yyyy-mm-dd}}.
  if components.length == 2 && components[0].length == 1 && components[1].length == 1
    begin
      date1 = Date.parse(components[0][0])
      date2 = Date.parse(components[1][0])
    rescue Exception => e
      STDERR.puts "Died on date1: #{components[0][0]}"
      STDERR.puts "Died on date2: #{components[1][0]}"
      STDERR.puts "Died on: #{tag}"
      raise
    end

    return {
      "year1" => date1.year,
      "month1" => date1.month,
      "day1" => date1.day,
      "precision1" => "day",

      "year2" => date2.year,
      "month2" => date2.month,
      "day2" => date2.day,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # Inject keys if components are values-only.
  # We can't use zip as we only want to inject the keys if we're dealing with numbers.
  keys = ["year1", "month1", "day1", "year2", "month2", "day2"]
  components = components.each_with_index.map { |c, i|
    if c.length == 1 && c[0].match?(/^\d+$/)
      [keys[i], c[0]]
    else
      c
    end
  }

  # Convert values to integers.
  components.map! { |kv| [kv[0], kv[1].nil? ? nil : kv[1].to_i] }

  # Merge and return result as hash.
  result = Hash[components]

  # Normalize.
  reject_keys = ["year", "month", "day"]
  reject_keys.each { |x| result[x+"1"] = result[x] if result.has_key?(x) }
  reject_keys.each { |x| result.delete(x) }

  # Remove all nil values.
  result.delete_if { |k,v| v.nil? }

  # Set precision.
  result["precision1"] = "year" if result.has_key? "year1"
  result["precision1"] = "month" if result.has_key? "month1"
  result["precision1"] = "day" if result.has_key? "day1"

  result["precision2"] = "year" if result.has_key? "year2"
  result["precision2"] = "month" if result.has_key? "month2"
  result["precision2"] = "day" if result.has_key? "day2"

  result["ongoing"] = ongoing

  result
end

def month_name_to_number(name)
  Date::MONTHNAMES.find_index { |x| (x||"").downcase.start_with? name }
end

def parse_date(date, title, year)
  orig_date = date.dup

  # the ruskies got us
  date.gsub!("Маrch", "March")

  date.downcase!

  # Garbage normalization!

  # Make the assumption that [[a|b]] refers to the date b
  date.gsub!(/\[\[.*?\|(.*?)\]\]/, '\1')

  # If our date starts with a link, assume it's an alias we can delete
  date.gsub!(/^[a-z ]*\[\[.*?\]\], /, "")

  # Replace non-breaking space with space
  date.gsub!("&nbsp;", " ")
  date.gsub!("{{nbsp}}", " ")
  date.gsub!("{{nbs}}", " ")
  # Remove small tags
  date.gsub!("<small>", "")
  date.gsub!("</small>", "")

  # Normalize certain terms
  date.gsub!("bce.", "bc")
  date.gsub!("b.c.", "bc")
  date.gsub!("bc.", "bc")
  date.gsub!("a.d", "ad")
  date.gsub!("ad.", "ad")
  date.gsub!("p.m", "pm")
  date.gsub!("pm.", "pm")
  date.gsub!("a.m", "am")
  date.gsub!("am.", "am")
  date.gsub!("(in progress)", "present")
  date.gsub!("''present''", "present")
  date.gsub!("''ongoing''", "present")
  date.gsub!("ongoing", "present")
  date.gsub!("current", "present")
  date.gsub!(" , ", ", ")

  # Remove newlines
  date.gsub!("<br>", " ")
  date.gsub!("<br/>", " ")
  date.gsub!("<br />", " ")
  date.gsub!("\n", " ")

  # Remove wikitext tags
  date.gsub!(/\<ref .*?\/\>/, "")
  date.gsub!(/\<ref.*?\>.*?\<\/ref\>/, "")
  date.gsub!(/\<sup.*?\>.*?\<\/sup\>/, "")
  date.gsub!(/\<!--.*?--\>/, "")
  date.gsub!(/\{\{rp.*?\}\}/, "")
  date.gsub!(/\{\{cn.*?\}\}/, "")
  date.gsub!(/\{\{clarify.*?\}\}/, "")
  date.gsub!(/\{\{sfn.*?\}\}/, "")
  date.gsub!(/\{\{efn.*?\}\}/, "")
  date.gsub!(/\{\{resize.*?\}\}/, "")
  date.gsub!(/\{\{dubious.*?\}\}/, "")
  date.gsub!(/\{\{cref.*?\}\}/, "")
  date.gsub!(/\{\{ref.*?\}\}/, "")
  date.gsub!(/\{\{\#tag:ref\|.*?\}\}/, "")
  date.gsub!(/\{\{citation needed.*?\}\}/, "")
  date.gsub!(/\{\{page needed.*?\}\}/, "")
  date.gsub!("{{-}}", "")
  date.gsub!("''(cancelled)''", "")
  date.gsub!("{{ubl|", "")
  current_date = Date.today
  date.gsub!("{{presentyear}}", current_date.year.to_s)
  date.gsub!("{{presentmonth}}", current_date.month.to_s)
  date.gsub!("{{presentday}}", current_date.day.to_s)

  # Unwrap tags
  date.gsub!(/\{\{nowrap\|(.*?)\}\}/, '\1')
  date.gsub!(/\{\{nowr\|(.*?)\}\}/, '\1')

  # We already know this is going to be approximate...
  date.gsub!("''circa''", "")
  date.gsub!("{{circa}}", "")
  date.gsub!(/\{\{circa\|(.*?)\}\}/, '\1')
  date.gsub!("{{c.}}", "")
  date.gsub!("c.", "")
  date.gsub!("circa", "")
  date.gsub!(/^~/, "")
  date.gsub!(/^\(as of\) /, "")
  date.gsub!("ca.", "")
  date.gsub!("'''c'''. ", "")
  date.gsub!("probably", "")

  # Remove hard-coded durations
  date.gsub!(/\((\d+ years)? *(\d+ months)? *&? *(\d+ days)?\)/, "")
  date.gsub!(/; \d+ years ago/, "")
  date.gsub!(/; \{\{age\|\d+\|\d+\|\d+\}\} years ago/, "")

  # Remove the day prefix from dates
  date.gsub!(/(sunday|monday|tuesday|wednesday|thursday|friday|saturday), /, "")

  # Normalize dashes
  date.gsub!("{{snd}}", "-")
  date.gsub!("{{snds}}", "-")
  date.gsub!("&mdash;", "-")
  date.gsub!("&ndash;", "-")
  date.gsub!("–", "-")
  date.gsub!("—", "-")
  date.gsub!("−", "-")
  date.gsub!("―", "-")
  date.gsub!("{{dash}}", "-")
  date.gsub!("{{ndash}}", "-")
  date.gsub!("{{endash}}", "-")
  date.gsub!("{{en dash}}", "-")
  date.gsub!("{{spaced endash}}", "-")
  date.gsub!("{{spaced en dash}}", "-")
  date.gsub!("{{spaced ndash}}", "-")
  date.gsub!(" - ", "-")
  date.gsub!(" -", "-")
  date.gsub!("- ", "-")
  date.gsub!(" to ", "-")
  date.gsub!(" through ", "-")
  date.gsub!("－", "-")
  # Come on, really?
  date.gsub!(/between (.*)? and (.*?)/, '\1-\2')
  date.gsub!(/^from /, '')

  # We can do without time.
  date.gsub!("night of", "")
  date.gsub!(/mid[- ]/, "")
  date.gsub!("predominately", "")
  date.gsub!("early", "")
  date.gsub!("late", "")
  date.gsub!(/\[\d\d:\d\d [a-z]+\]/, "") # [13:45 PDT]
  date.gsub!(/\d?\d:\d\d ?[ap]m-\d?\d:\d\d ?[ap]m/, "") # 11:45 am - 12:30 pm
  date.gsub!(/\d?\d:\d\d ?[ap]m/, "") # 11:45 am
  date.gsub!(/\d\d:\d\d/, "") # 11:45
  date.gsub!("unknown, ", "")
  date.gsub!("shortly after", "")
  date.gsub!("since", "")
  date.gsub!("throughout the", "")
  date.gsub!(/spring( of)?/, "")
  date.gsub!(/autumn( of)?/, "")
  date.gsub!(/winter( of)?/, "")
  date.gsub!(/summer( of)?/, "")
  date.gsub!(/beginning( of)?/, "")
  date.gsub!("during the night", "")
  date.gsub!("solstice", "")
  date.gsub!(/\bcdt\b/, "")

  # Remove suffixes and prefixes
  date.gsub!(/[,\.\|;] *$/, "")
  date.gsub!(/^[\.,:;] */, "")
  date.gsub!("?", "")

  # Remove English numerical suffixes
  date.gsub!(/(\d)(st|nd|rd|th)/, '\1')

  # Remove "of" from "March of 1287"
  date.gsub!(/([a-z]+) +of +(\d+)/, '\1 \2')

  # Normalize spaces
  date.gsub!("  ", " ")

  # Remove dots after numbers
  date.gsub!(/\b(\d+)\./, '\1')

  # Remove useless parameters to templates
  date.gsub!(/\ *\| *time.*/, "")
  date.gsub!(/\ *\| *page.*/, "")
  date.gsub!(/\ *\| *place.*/, "")
  date.gsub!(/\ *\| *df=[ a-z]+/, "")
  date.gsub!(/\ *\| *mf=[ a-z]+/, "")
  date.gsub!(/\ *\| *p=[ a-z]+/, "")
  date.gsub!(/\ *\| *br=[ a-z]+/, "")
  date.gsub!(/\ *\| *sep=[ a-z]+/, "")
  date.gsub!(/\ *\| *range=[ a-z]+/, "")

  # Remap some template names
  date.gsub!("{{date start", "{{start date")

  # y'all are cooked over at wikipedia
  # 25 July–{{end date|1995|10|17}} -> {{start date|1995|07|25}}–{{end date|1995|10|17}}
  date.gsub!(/(\d+) ([a-z]+)-(\{\{end date\|(\d+)\|.*?\}\})/) { |m|
    "{{start date|#{$4}|#{month_name_to_number($2)}|#{$1}}}-#{$3}"
  }

  # Determine whether this is an ongoing event.
  ongoing = false
  if date.include? "-present"
    date.gsub!("-present", "")
    ongoing = true
  end

  # {{age in ...|date fields|date fields}}
  m = date.match /\{\{age.*?\}\}/
  if m != nil
    return parse_age_ymwd(m[0], ongoing)
  end

  # Remove parenthesised suffixes (these are almost always worthless notes)
  date.gsub!(/\(.*?\)$/, "")

  # Artificially insert a dash between back-to-back start/end-date tags
  date.gsub!(/(\{\{start-date\|.*?\}\})(\{\{end-date\|.*?\}\})/, '\1-\2')

  # {{[a-z]* ?date( and age)?( and years ago)?|year|month|day}}
  date.gsub!(/\{\{[a-z]* ?date(?: and age)? *(?: and years ago)? *\|(\d+)\|(\d+)\|(\d+)\}\}/) { |m|
    day = $3.to_i
    month = $2.to_i
    day, month = month, day if month > 12
    "#{day} #{Date::MONTHNAMES[month].downcase} #{$1}"
  }

  # {{start and end date(?:s)?|year|month|day|year|month|day}}
  date.gsub!(/\{\{start and end date(?:s)?\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\|(\d+)\}\}/) { |m|
    day1 = $3.to_i
    month1 = $2.to_i
    day1, month1 = month1, day1 if month1 > 12

    day2 = $5.to_i
    month2 = $2.to_i
    day2, month2 = month1, day2 if month2 > 12

    "#{day1} #{Date::MONTHNAMES[month1].downcase} #{$1}-#{day2} #{Date::MONTHNAMES[month2].downcase} #{$4}"
  }

  # Extremely hacky workaround for start/end-date tags
  date.gsub!(/\{\{(?:(?:start|end)-)?date\| *([^\|]+)\}\}/, '\1')
  date.gsub!(/\{\{(?:(?:start|end)-)?date\| *([^\|]+)\| *(?:[^\|]+)\}\}/, '\1')

  # Remap partial YYYY-MMM date tags to parseable dates.
  # {{[a-z]* date|2013|12}} -> December 2013
  date.gsub!(/\{\{[a-z]* *date\|(\d+)\|(\d+)\}\}/) { "#{Date::MONTHNAMES[$2.to_i].downcase} #{$1}" }

  # {{[a-z]* date|2013}} -> 2013
  date.gsub!(/\{\{[a-z]* *date\|(\d+)\}\}/) { "#{$1}" }

  # Remap two-day events to a range
  date.gsub!(/ (\d+)\/(\d+)([ ,])/, ' \1-\2\3')
  date.gsub!(/^(\d+)\/(\d+) /, '\1-\2 ')

  # Experimental: un-Americanize dates
  # mmm dd-mmm dd -> dd mmm-dd mmm
  date.gsub!(/(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2})-(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2})\b/, '\2 \1-\4 \3')
  # mmm dd-dd -> dd-dd mmm
  date.gsub!(/(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2})-(\d{1,2})\b/) { |m|
    $2.to_i < $3.to_i ? "#{$2}-#{$3} #{$1}" : $& # Don't remap if the date range doesn't make sense (otherwise Feb 28-19 April 1993 gets remapped to 28-19 Feb April 1993)
  }
  # mmm dd-dd, yyyy -> dd-dd mmm yyyy
  date.gsub!(/(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d+)-(\d+),? (\d+)/, '\2-\3 \1 \4')
  # mmm dd, yyyy -> dd mmm yyyy
  date.gsub!(/(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d+),? (\d+)/, '\2 \1 \3')

  # Inject BC into a range
  # 589-587 bc -> 589 bc-587 bc
  date.gsub!(/(.*?\d+)(?!bc)-(.*?) bc/, '\1 bc-\2 bc')

  # Remap BCE dates to negative CE dates
  date.gsub!(/(\d+) \bbc(e)?\b/) { |m| (1 - $1.to_i).to_s }
  date.gsub!(/(\d+) century \bbc(e)?\b/) { |m| (1 - $1.to_i).to_s }

  # If we encounter an Islamic calendar date that's followed by a maybe-Gregorian date,
  # strip the Islamic date and hope for the best.
  # 10 muharram 61 ah, october 10, 680 -> october 10, 680
  date.gsub!(/\d+ [a-z]+ \d+ ah,(.*\d+)/, '\1')
  # 13 March 624 CE/17 Ramadan, 2 AH -> 13 March 624 CE
  date.gsub!(/(.*? ce)\/.*? ah/, '\1')

  # Remove the AD/CE pre/suffix
  date.gsub!(/(\d+) \b(ad|ce)\b/, '\1')
  date.gsub!(/\b(ad|ce)\b (\d+)/, '\2')

  # If this is literally a link, remove the link wrapper
  date.gsub!(/^\[\[(.*?)\]\]$/, '\1')

  # Remove interstital Julian calendar dates.
  # 13 may (2 may os), 1790 -> 13 may, 1790
  date.gsub!(/(.*?) \(.*? os\)(.*?)/, '\1\2')

  # Extract new-style dates from OldStyleDateNY.
  date.gsub!(/\{\{oldstyledateny\|(.*?)\|.*?\}\}/, '\1')

  # Remove external links.
  date.gsub!(/\[.*?\]$/, "")

  # At this point, we start looking for exclusive matches.
  # Strip the line of any whitespace to ensure we get a full match.
  date.strip!

  # Remove suffixes and prefixes (again)
  date.gsub!(/[,\.\|\?\};]* *$/, "")
  date.gsub!(/^[\.,:;] */, "")

  # If we have a partial day-month and year in the title, merge them
  # 21-23 September (date), Gymnastics at the 2014 Asian Games – Men's artistic team (title)
  # -> 21-23 September 2014
  m = date.match /^(?:\d{1,2}-)?\d{1,2} (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+$/
  if m != nil
    m = title.match /(\d\d\d\d)/
    if m != nil then
      date = "#{date} #{m[0]}"
    end
  end
  # 21 August-23 September (date), Gymnastics at the 2014 Asian Games – Men's artistic team (title)
  # -> 21 August-23 September 2014
  m = date.match /^\d{1,2} (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+-\d{1,2} (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+$/
  if m != nil
    m = title.match /(\d\d\d\d)/
    if m != nil then
      date = "#{date} #{m[0]}"
    end
  end
  # August 10-December 1 (date), Nitro World Games 2018
  # -> August 10-December 1 2018
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+ \d{1,2}-(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+ \d{1,2}$/
  if m != nil
    m = title.match /(\d\d\d\d)/
    if m != nil then
      date = "#{date} #{m[0]}"
    end
  end
  # If we've been provided with a year and this looks like it could be a date, add the year
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december)+ \d{1,2}$/
  if m != nil && year != nil
    date = "#{date} #{year}"
  end

  # yyyy-mm-dd
  m = date.match /^(-?\d+)\-(\d{1,2})\-(\d{1,2})$/
  if m != nil
    puts "yyyy-mm-dd: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => m[2].to_i,
      "day1" => m[3].to_i,
      "precision1" => "day",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # dd mmm yyyy-yyyy
  m = date.match /^(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *(-?\d+) *- *(-?\d+)$/
  if m != nil
    puts "dd mmm yyyy-yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[2]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => m[4].to_i,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "year",
      "ongoing" => ongoing
    }
  end

  # dd mmm,? yyyy-mmm,? yyyy
  m = date.match /^(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  if m != nil
    puts "dd mmm,? yyyy-mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[2]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => m[5].to_i,
      "month2" => month_name_to_number(m[4]),
      "day2" => nil,
      "precision2" => "month",
      "ongoing" => ongoing
    }
  end

  # dd mmm,? yyyy-dd mmm,? yyyy
  m = date.match /^(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+) *- *(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  if m != nil
    puts "dd mmm,? yyyy-dd mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[2]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => m[6].to_i,
      "month2" => month_name_to_number(m[5]),
      "day2" => m[4].to_i,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # dd mmm-dd mmm,? yyyy
  m = date.match /^(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *- *(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  if m != nil
    puts "dd mmm-dd mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[5].to_i,
      "month1" => month_name_to_number(m[2]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => m[5].to_i,
      "month2" => month_name_to_number(m[4]),
      "day2" => m[3].to_i,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # dd-dd mmm,? yyyy
  m = date.match /^(\d{1,2}) *- *(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  # Employing a pathological sanity check here: dd2 > dd1.
  # This prevents yyyy - dd mmm yyyy being handled by this handler.
  if m != nil && m[2].to_i > m[1].to_i
    puts "dd-dd mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[4].to_i,
      "month1" => month_name_to_number(m[3]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => m[4].to_i,
      "month2" => month_name_to_number(m[3]),
      "day2" => m[2].to_i,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # dd mmm,? yyyy
  m = date.match /^(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  if m != nil
    puts "dd mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[2]),
      "day1" => m[1].to_i,
      "precision1" => "day",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # # mmm dd,? yyyy-mmm dd,? yyyy
  # m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}),? (-?\d+) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}),? (-?\d+)$/
  # if m != nil
  #   puts "mmm dd,? yyyy-mmm dd,? yyyy: #{date} #{m}" if DEBUG_PARSE
  #   return {
  #     "year1" => m[3].to_i,
  #     "month1" => month_name_to_number(m[1]),
  #     "day1" => m[2].to_i,
  #     "precision1" => "day",

  #     "year2" => m[6].to_i,
  #     "month2" => month_name_to_number(m[4]),
  #     "day2" => m[5].to_i,
  #     "precision2" => "day",
  #     "ongoing" => ongoing
  #   }
  # end

  # # mmm dd,? yyyy-mmm,? yyyy
  # m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}),? (-?\d+) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  # if m != nil
  #   puts "mmm dd,? yyyy-mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
  #   return {
  #     "year1" => m[3].to_i,
  #     "month1" => month_name_to_number(m[1]),
  #     "day1" => m[2].to_i,
  #     "precision1" => "day",

  #     "year2" => m[5].to_i,
  #     "month2" => month_name_to_number(m[4]),
  #     "day2" => nil,
  #     "precision2" => "month",
  #     "ongoing" => ongoing
  #   }
  # end

  # # mmm dd-mmm,? yyyy
  # m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  # if m != nil
  #   puts "mmm dd-mmm yyyy: #{date} #{m}" if DEBUG_PARSE
  #   return {
  #     "year1" => m[4].to_i,
  #     "month1" => month_name_to_number(m[1]),
  #     "day1" => m[2].to_i,
  #     "precision1" => "day",

  #     "year2" => m[4].to_i,
  #     "month2" => month_name_to_number(m[3]),
  #     "day2" => nil,
  #     "precision2" => "month",
  #     "ongoing" => ongoing
  #   }
  # end

  # # mmm dd-mmm dd,? yyyy
  # m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}),? (-?\d+)$/
  # if m != nil
  #   puts "mmm dd-mmm dd,? yyyy: #{date} #{m}" if DEBUG_PARSE
  #   return {
  #     "year1" => m[5].to_i,
  #     "month1" => month_name_to_number(m[1]),
  #     "day1" => m[2].to_i,
  #     "precision1" => "day",

  #     "year2" => m[5].to_i,
  #     "month2" => month_name_to_number(m[3]),
  #     "day2" => m[4].to_i,
  #     "precision2" => "day",
  #     "ongoing" => ongoing
  #   }
  # end

  # # mmm dd-dd,? yyyy
  # m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}) *- *(\d{1,2}),? (-?\d+)$/
  # if m != nil
  #   puts "mmm dd-dd,? yyyy: #{date} #{m}" if DEBUG_PARSE
  #   return {
  #     "year1" => m[4].to_i,
  #     "month1" => month_name_to_number(m[1]),
  #     "day1" => m[2].to_i,
  #     "precision1" => "day",

  #     "year2" => m[4].to_i,
  #     "month2" => month_name_to_number(m[1]),
  #     "day2" => m[3].to_i,
  #     "precision2" => "day",
  #     "ongoing" => ongoing
  #   }
  # end

  # mmm dd,? yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (\d{1,2}),? (-?\d+)$/
  if m != nil
    puts "mmm dd,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => m[2].to_i,
      "precision1" => "day",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # mmm,? yyyy-mmm,? yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? *(-?\d+) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? *(-?\d+)$/
  if m != nil
    puts "mmm,? yyyy-mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[2].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => nil,
      "precision1" => "month",

      "year2" => m[4].to_i,
      "month2" => month_name_to_number(m[3]),
      "day2" => nil,
      "precision2" => "month",
      "ongoing" => ongoing
    }
  end

  # mmm-mmm,? yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? *(-?\d+)$/
  if m != nil
    puts "mmm-mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[3].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => nil,
      "precision1" => "month",

      "year2" => m[3].to_i,
      "month2" => month_name_to_number(m[2]),
      "day2" => nil,
      "precision2" => "month",
      "ongoing" => ongoing
    }
  end

  # mmm yyyy-dd mmm,? yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *(-?\d+) *- *(\d{1,2}) (jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *,? (-?\d+)$/
  if m != nil
    puts "mmm yyyy-dd mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[2].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => nil,
      "precision1" => "month",

      "year2" => m[5].to_i,
      "month2" => month_name_to_number(m[4]),
      "day2" => m[3].to_i,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # mmm,? yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? *(-?\d+)$/
  if m != nil
    puts "mmm,? yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[2].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => nil,
      "precision1" => "month",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # yyyys-yyyys
  m = date.match /^(-?\d+)s-(-?\d+)s$/
  if m != nil
    puts "yyyys-yyyys: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "decade",

      "year2" => m[2].to_i,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "decade",
      "ongoing" => ongoing
    }
  end

  # yyyys-yyyy
  m = date.match /^(-?\d+)s-(-?\d+)$/
  if m != nil
    puts "yyyys-yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "decade",

      "year2" => m[2].to_i,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "year",
      "ongoing" => ongoing
    }
  end

  # yyyys
  m = date.match /^(-?\d+)s$/
  if m != nil
    puts "yyyys: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "decade",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # yyyy-dd mmm yyyy
  m = date.match /^(\d+) *- *(\d{1,2}) *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december),? (-?\d+)$/
  if m != nil
    puts "yyyy-dd mmm yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "year",

      "year2" => m[4].to_i,
      "month2" => month_name_to_number(m[3]),
      "day2" => m[2].to_i,
      "precision2" => "day",
      "ongoing" => ongoing
    }
  end

  # mmm yyyy-yyyy
  m = date.match /^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) *(-?\d+) *- *(-?\d+)$/
  if m != nil
    puts "mmm yyyy-yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[2].to_i,
      "month1" => month_name_to_number(m[1]),
      "day1" => nil,
      "precision1" => "month",

      "year2" => m[3].to_i,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "year",
      "ongoing" => ongoing
    }
  end

  # yyyy-mmm yyyy
  m = date.match /^(-?\d+) *- *(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|september|oct|october|nov|november|dec|december) (-?\d+)$/
  if m != nil
    puts "yyyy-mmm yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "year",

      "year2" => m[3].to_i,
      "month2" => month_name_to_number(m[2]),
      "day2" => nil,
      "precision2" => "month",
      "ongoing" => ongoing
    }
  end

  # yyyy-yyyy
  m = date.match /^(-?\d+) *- *(-?\d+)$/
  if m != nil
    y1 = m[1]
    y2 = m[2]

    # 1550-1 -> 1550-1551
    # Assume this isn't being done on BC dates
    if y2.length < y1.length && !y1.start_with?("-") && !y2.start_with?("-")
      y2 = y1[0..y1.length-y2.length-1] + y2
    end

    puts "yyyy-yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => y1.to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "year",

      "year2" => y2.to_i,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "year",
      "ongoing" => ongoing
    }
  end

  # yyyy
  m = date.match /^(-?\d+)$/
  if m != nil
    puts "yyyy: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => m[1].to_i,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "year",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # xx century-xx century
  m = date.match /^(-?\d+) century-(-?\d+) century$/
  if m != nil
    puts "xx century-xx century: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => (m[1].to_i - 1) * 100,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "century",

      "year2" => (m[2].to_i - 1) * 100,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "century",
      "ongoing" => ongoing
    }
  end

  # xx-xx centur(y|ies)
  m = date.match /^(-?\d+) *- *(-?\d+) centur(y|ies)$/
  if m != nil
    puts "xx-xx centur(y|ies): #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => (m[1].to_i - 1) * 100,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "century",

      "year2" => (m[2].to_i - 1) * 100,
      "month2" => nil,
      "day2" => nil,
      "precision2" => "century",
      "ongoing" => ongoing
    }
  end

  # xx century
  m = date.match /^(-?\d+) century$/
  if m != nil
    puts "xx century: #{date} #{m}" if DEBUG_PARSE
    return {
      "year1" => (m[1].to_i - 1) * 100,
      "month1" => nil,
      "day1" => nil,
      "precision1" => "century",

      "year2" => nil,
      "month2" => nil,
      "day2" => nil,
      "precision2" => nil,
      "ongoing" => ongoing
    }
  end

  # Try replacing "and" with "-" and see if that gets us anywhere.
  maybe_date = orig_date.gsub(/\band\b/, "-")
  if maybe_date != orig_date
    return process_date(maybe_date, title, year)
  end

  date
end

def fixup_date(date)
  return date unless date.class == Hash

  # WHYYYYYY?
  # Swap month and days if required.
  if date["month1"] != nil && date["day1"] != nil && date["month1"] > 12 then
    month = date["month1"]
    date["month1"] = date["day1"]
    date["day1"] = month
  end
  if date["month2"] != nil && date["day2"] != nil && date["month2"] > 12 then
    month = date["month2"]
    date["month2"] = date["day2"]
    date["day2"] = month
  end

  date
end

def process_date(date, title = nil, year = nil)
  begin
    fixup_date(parse_date(date, title, year))
  rescue => e
    STDERR.puts("process_date: died on '#{date}' from '#{title}'")
    raise
  end
end

# Some jokers like to fuck up Wikipedia dates. This checks for validity
# so that they're filtered out.
def validate_date_structure(date)
  if !date['year1'].nil? && !date['month1'].nil? && !date['day1'].nil?
    return false unless Date.valid_date?(date['year1'], date['month1'], date['day1'])
  end

  if !date['year2'].nil? && !date['month2'].nil? && !date['day2'].nil?
    return false unless Date.valid_date?(date['year2'], date['month2'], date['day2'])
  end

  true
end

def process_event(event, title)
  date = event["date"].dup
  return nil if date.nil?

  # This is a crappy heuristic, but...
  title = event["title"] if event["title"] != nil && !title.match?(/\d{4}/) && event["title"].match?(/\d{4}/)
  event["old_date"] = event["date"].dup

  new_date = process_date(date, title, event["year"] != nil ? event["year"].to_i : nil)
  event["date"] = new_date if validate_date_structure(new_date)

  event
end

def process_page(page)
  title = page["page_title"]

  page["events"] = page["events"]
    .map { |e| process_event(e, title) }

  page
end

return unless $0 == __FILE__

puts "process: load"
data = JSON.parse(File.read('data/semiprocessed-events.json'))
puts "process: remove empty dates from #{data.length} events"
data.each { |p|
  p["events"].delete_if {
    |e| e["date"].nil? || e["date"].empty?
  }
}
puts "process: remove pages with no events from #{data.length} events"
data.delete_if { |p| p["events"].empty? }

puts "process: process pages from #{data.length} events"
pages = Parallel.map(data) { |e| process_page(e) }

puts "process: gathering statistics from #{pages.length} pages"
events_count = pages.map { |p| p["events"].length }.sum
parsed_count = pages.map { |p| p["events"].map { |e| e["date"].class == Hash ? 1 : 0 }.sum }.sum
puts "process: parsed date count - #{parsed_count}/#{events_count} (#{(parsed_count.to_f * 100/events_count).round(2)}%)"

puts "process: write bad dates"
bad_dates = pages
  .map { |p|
    p["events"].filter { |e| e["date"].class != Hash }
  }
  .filter { |es| !es.empty? }
  .flatten
File.write('data/bad-dates.json', JSON.generate(bad_dates))

puts "process: remove old dates"
pages.each { |p|
  p["events"].each { |e| e.delete("old_date") }
  p["events"].delete_if { |e| e["date"].class != Hash }
}

puts "process: remove pages with no events after processing from #{pages.length} pages"
pages = pages.filter { |p| !p["events"].empty? }

puts "process: write #{pages.length} pages"
File.write('data/processed-events.json', JSON.generate(pages))
puts "process: done"
