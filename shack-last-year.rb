#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'date'
require 'net/http'
require 'cgi'
require 'uri'
require 'yaml'

def get_start_date()
  today = Date.today
  print("Getting start date for date: %s\n" % today)
  last_year = today << 12 # today.prev_year isn't supported in Ruby 1.8 :(
  return last_year
end

def get_lols_on_date(date)
  print("Getting LOLs for %s\n" % date)
  date_str = date.strftime('%m/%d/%Y')
  uri = URI.parse('http://www.lmnopc.com/greasemonkey/shacklol/api.php?format=json&date=%s&tag=lol' % date_str)
  resp = Net::HTTP.get_response(uri)
  resp_json = JSON.parse(resp.body)
  return resp_json
end

def get_sorted_lols(start_date, end_date)
  print("Getting all LOLs for %s to %s\n" % [start_date, end_date])
  all_lols = []
  (start_date .. end_date).each do |a_date|
    daily_lols = get_lols_on_date(a_date)
    all_lols = all_lols + daily_lols
  end

  all_lols.sort! do |a, b|
    b['tag_count'].to_i <=> a['tag_count'].to_i
  end

  return all_lols
end

def root_post_content(start_date, end_date, num_lols)
  print("Generating root content for %s LOLs between %s and %s\n" % [num_lols, start_date, end_date])
  def ordinalize(number)
    if (11..13).include?(number.to_i.abs % 100)
      "#{number}th"
    else
      case number.to_i.abs % 10
      when 1; "#{number}st"
      when 2; "#{number}nd"
      when 3; "#{number}rd"
      else    "#{number}th"
      end
    end
  end

  today = Date.today
  day_ord = ordinalize(today.day)  
  start_str = start_date.strftime('%B %-d, %Y')
  end_str = end_date.strftime('%B %-d, %Y')
  content = "*[y{Hey it's the beginning of another week!}y]* Got a case of the Mondays? Cheer up with *[b{last year's}b]* *[y{LOLs}y]*.\n\nComing up: the top %s y{LOLed}y posts from b{%s}b to b{%s}b.\n" %
    [num_lols, start_str, end_str]
  return content
end

def convert_html_to_post(raw)
  raw = CGI.unescapeHTML(raw)
  raw.gsub!("\r", "")
  output = ''
  index = 0
  end_tags = []
  while index < raw.length do
    if raw[index, 1] != '<'
      # Nothing special, just copy over
      output << raw[index, 1]
      index += 1
      next
    end

    end_tag_index = raw.index('>', index) + 1
    tag_length = end_tag_index - index
    tag = raw[index, tag_length]
    if raw[index + 1, 1] == '/'
      # Processing a close tag (</)
      if tag == '</b>' or tag == '</strong>'
        output << ']*'
      elsif tag == '</i>' or tag == '</em>'
        output << ']/'
      elsif tag == '</u>'
        output << ']_'
      elsif tag == '</span>'
        output << end_tags.pop()
      end

      index = end_tag_index
      next
    end

    # Processing a new tag
    end_tag_name_index = tag.index(/[^\w]/, 1)
    tag_name_length = end_tag_name_index - 1
    tag_name = tag[1, tag_name_length]
    if tag_name == 'br'
      output << "\n"
    elsif tag_name == 'b' or tag_name == 'strong'
      output << '*['
    elsif tag_name == 'i' or tag_name == 'em'
      output << '/['
    elsif tag_name == 'u'
      output << '_['
    elsif tag_name == 'span'
      class_start = tag.index('class="')
      if class_start
        class_start += 7
        class_end = tag.index('"', class_start + 1)
        class_length = class_end - class_start
        class_name = tag[class_start, class_length]
        if class_name == "jt_blue"
          output << 'b{'
          end_tags.push('}b')
        elsif class_name == "jt_red"
          output << 'r{'
          end_tags.push('}r')
        elsif class_name == "jt_green"
          output << 'g{'
          end_tags.push('}g')
        elsif class_name == "jt_yellow"
          output << 'y{'
          end_tags.push('}y')
        elsif class_name == "jt_sample"
          output << 's['
          end_tags.push(']s')
        elsif class_name == "jt_spoiler"
          output << 'o['
          end_tags.push(']o')
        elsif class_name == "jt_strike"
          output << '-['
          end_tags.push(']-')
        elsif class_name == "jt_lime"
          output << 'l['
          end_tags.push(']l')
        elsif class_name == "jt_pink"
          output << 'p['
          end_tags.push(']p')
        elsif class_name == "jt_orange"
          output << 'n['
          end_tags.push(']n')
        elsif class_name == "jt_fuchsia"
          output << 'f['
          end_tags.push(']f')
        elsif class_name == "jt_olive"
          output << 'e['
          end_tags.push(']e')
        elsif class_name == "jt_quote"
          output << 'q['
          end_tags.push(']q')
        end
      end
    end

    index = end_tag_index
  end

  print("Converted raw LOL to shacktags\n")
  print("Input : %s\n" % raw)
  print("Output: %s\n" % output)
  return output
end

def lol_post_content(place, lol)
  print("Generating LOL post content for LOL #{place}\n")
  username = lol['author']
  lol_count = lol['tag_count']
  post_id = lol['id']
  body = lol['body']
  content = "_[*[##{place}]* by y{#{username}}y with #{lol_count} LOLs]_: http://www.shacknews.com/chatty?id=#{post_id}"
  if lol['category'] == 'nws' or body =~ /NWS/
    content += " r{(NWS post detected!)}r"
  end
  content += "\n"
  display_body = convert_html_to_post(body)
  if display_body.length < 700
    content += display_body
  else
    content += display_body[0, 700] + "..."
  end
  content += "\n\n"
  return content
end

def make_post(username, password, content, parent_id = nil)
  print("Sending post (with parent %s) for content:\n%s\n" % [parent_id, content])
  uri = URI.parse('http://www.shacknews.com/api/chat/create/17.json')
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)

  request.basic_auth(username, password)
  request['User-Agent'] = 'RubyShackAPI 1.0'
  form_data = {'content_type_id' => 17, 'content_id' => 17, 'body' => content}
  if parent_id
    form_data['parent_id'] = parent_id
  end
  request.set_form_data(form_data)

  response = http.request(request)
  print("Response [%s]: %s\n\n" % [response.code, response.body])
  if response.code.to_i != 200
    print("Invalid response code\n")
    return nil
  end

  response_json = JSON.parse(response.body)
  return response_json['data']['post_insert_id']
end

def convert_lols_to_posts(all_lols, num_lols)
  lols_per_post = 5
  print("Converting all posts to top %s posts with %s LOLs per post\n" % [num_lols, lols_per_post])
  lol_posts = []
  cur_lol_post_content = ''
  top_lols = all_lols[0, num_lols]
  top_lols.each_with_index do |a_lol, index|
    if index > 0 and index % lols_per_post == 0
      lol_posts.unshift(cur_lol_post_content)
      cur_lol_post_content = ''
    end
    cur_lol_post_content = lol_post_content(index + 1, a_lol) + cur_lol_post_content
  end
  lol_posts.unshift(cur_lol_post_content)  
  return lol_posts
end

if ARGV.length != 1
  print "Missing config path."
  exit
end

config_path = ARGV[0]
config = YAML.load_file(config_path)
username = config['shack_username']
password = config['shack_password']
num_days = config['num_days']
num_lols = config['num_lols']
post_sleep_seconds = config['post_sleep_seconds']

start_date = get_start_date()
end_date = start_date + num_days

sorted_lols = get_sorted_lols(start_date, end_date)
lol_posts = convert_lols_to_posts(sorted_lols, num_lols)

if lol_posts.length == 0
  print "No LOLs to post!\n"
  exit
end

root_content = root_post_content(start_date, end_date, num_lols)
root_id = make_post(username, password, root_content) #, 31065701)

lol_posts.each do |lol_post|
  sleep(post_sleep_seconds)
  make_post(username, password, lol_post, root_id)
end
