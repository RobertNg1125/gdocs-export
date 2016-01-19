#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'

require 'open-uri'

@source = ARGF.read

@doc = Nokogiri::HTML(@source)

# download all referenced images (they have absolute URLs)
@doc.css("img").each do |x|
  uri = x['src']
  name = File.basename(uri)
  name_with_ext = "#{name}.jpg"
  path = "./#{name_with_ext}"
  unless File.exists?(path)
    File.open(path,'wb'){ |f| f.write(open(uri).read) }
  end
  x['src'] = "#{name_with_ext}"
end


# support Google Docs title format, this prepares it for extract_metadata
@doc.css("p.title").each do |x|
  x.replace("<h1 class='ew-pandoc-title'>#{x.text}</h1>")
end

# support Google Docs subtitle format; this prepares it for extract_metada
@doc.css("p.subtitle").each do |x|
  x.replace("<h1 class='ew-pandoc-subtitle'>#{x.text}</h1>")
end

# fix bold tags; in the source:
#  .c14{font-weight:bold}
#  <span class="c14">Bold Text </span>
bold_classes = @source.scan(/\.(c\d+)\{font-weight:bold\}/)
bold_classes.each do |cssClass|
  @doc.css("span.#{cssClass[0]}").each do |x|
    x.name = "strong"
  end
end

# fix italic tags; in the source:
#  .c16{font-style:italic}
#  <span class="c16">Italic Text</span>
@source.scan(/\.(c\d+)\{font-style:italic\}/).each do |cssClass|
  @doc.css("span.#{cssClass[0]}").each do |x|
    x.name = "em"
  end
end

# fix underline tags; in the source:
#  .c13{text-decoration: underline}
#  <span class="c13">Underline Text</span>
#  Because pandoc doesn't support <u>, we make it into h1.underline
#  and rely on custom filtering to convert to LaTeX properly.
@source.scan(/\.(c\d+)\{text-decoration:underline\}/).each do |cssClass|
  @doc.css("span.#{cssClass[0]}").each do |x|
    x.replace("<span class='underline'>#{x.content}</s>")
  end
end

# sometimes images are placed inside a heading tag, which crashes latex
@doc.css('h1,h2,h3,h4,h5,h6').>('img').each do |x|
  x.parent.replace(x)
end

@doc.css('div').each do |x|
  # header: first div in body
  if (!x.previous_sibling && !x.previous_element)
    x.replace("<h1 class='ew-pandoc-header'>#{x.inner_text}</h1>")
  end

  # footer: last div in body
  if (!x.next_sibling && !x.next_element)
    x.replace("<h1 class='ew-pandoc-footer'>#{x.inner_text}</h1>")
  end
end


# remove empty nodes (google docs has lots of them, especially with pagebreaks)
# must come before pagebreak processing
@doc.css('h1,h2,h3,h4,h5,h6').each do |x|
  x.remove if x.text =~ /^\s*$/
end

# Rewrite page breaks into something pandoc can parse
# <hr style="page-break-before:always;display:none;">
@doc.css('hr[style="page-break-before:always;display:none;"]').each do |x|
  x.replace("<h1 class='ew-pandoc-pagebreak' />")
end

# Get the zero-based depth of a list
def list_depth(list)
  klasses = list['class'] or return 0
  klass = klasses.split.each do |klass|
    md = /^lst-kix_.*-(\d+)/.match(klass) or next
    return md[1].to_i
  end
  return 0
end

# Fixup lists
# Google Docs exports nested lists as separate lists right next to each other.
# Pass 1: Figure out the depth of each list
depths = []
@doc.css('ul, ol').each do |list|
  depth = list_depth(list)
  (depths[depth] ||= []) << list
end
# Pass 2: In reverse-depth order, coalesce lists
depths.to_enum.with_index.reverse_each do |lists, depth|
  next unless lists
  lists.reverse_each do |list|
    # If the previous item is not a list, we're fine
    prev = list.previous
    next unless %w[ol ul].include?(prev.name)

    # p [depth, list_depth(prev)]
    if list_depth(prev) == depth
      # Same depth, append our li's to theirs
      prev.add_child(list.children)
      list.remove
    else
      # Lesser depth, append us to their last item
      prev.xpath('li').last.add_child(list)
    end
  end
end

html = @doc.to_html
puts html

# trying to fix encoding bug introduced by ruby1.9.3 or nokogori 1.6
# &nbsp; are converted to strange characters, instead of staying as they are
# puts @doc.to_html.encode('utf-8')
# puts @doc.to_html.encode('iso-8859-1').encode('utf-8')
# nbsp = Nokogiri::HTML("&nbsp;").text
# html.gsub(nbsp, "&nbsp;")


# TODO: ensure neither title or subtitle occur more than once, or are empty
# TODO: write some tests
