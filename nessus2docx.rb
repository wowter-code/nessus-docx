#!/usr/bin/env ruby

$stderr.sync = true

begin
  require 'ruby-nessus'
rescue LoadError
  STDERR.puts "The ruby-nessus gem could not be loaded, is the latest version installed?"
  STDERR.puts "-> git clone https://github.com/mephux/ruby-nessus"
  STDERR.puts "-> cd ruby-nessus && gem build ruby-nessus.gemspec && gem install ruby-nessus-*.gem"
  exit 1
end
begin
  require 'sablon'
rescue LoadError
  STDERR.puts "The sablon gem could not be loaded, is it installed?"
  STDERR.puts "-> gem install sablon"
  exit 1
end
begin
  require "docopt"
rescue LoadError
  STDERR.puts "The docopt gem could not be loaded, is it installed?"
  STDERR.puts "-> gem install docopt"
  exit 1
end

doc = <<DOCOPT
This script accepts Nesses scan results and generates a Word document containing the 
discovered findings listed by severity. Informational severity findings are 
ignored by default.

Usage:
  #{__FILE__} -o <docx> <nessus>...
  #{__FILE__} -o <docx> [--critical] [--high] [--medium] [--low] [--info] <nessus>...
  #{__FILE__} -o <docx> [--all] <nessus>...
  #{__FILE__} -h | --help

Options:
  -o, --output=<docx>    The generated document.
  --all                    Shorthand to output all severity levels.
  --critical               Output critical severity findings.
  --high                   Output high severity findings.
  --medium                 Output medium severity findings.
  --low                    Output low severity findings.
  --info                   Output info severity findings.
  -h, --help               Show this output.

DOCOPT

begin
  options = Docopt::docopt(doc)
rescue Docopt::Exit => e
  STDERR.puts e.message
  exit 1
end

# check arguments

options['<nessus>'].each do |file|
  if !File.exist?(file)
    STDERR.puts "[!] #{file} does not exist!"
    exit 1
  end
end

# variables

findings = Hash.new
criticals = Array.new
highs = Array.new
mediums = Array.new
lows = Array.new
informationals = Array.new

# process nessus files

# title
# severity
# cvss
# description
# remediation
# reference
# systems affected
# notes

options['<nessus>'].each do |nessus|
  puts "[+] Processing #{nessus}"
  RubyNessus::Parse.new(nessus) do |scan|
    scan.hosts.each do |host|
      host.events.each do |event|
        #next if event.severity == 0 and not options['--all']
        next if event.severity == 4 && !options['--all'] && (options['--high'] || options['--medium'] || options['--low'] || options['--info'])
        next if event.severity == 3 && !options['--all'] && (options['--critical'] || options['--medium'] || options['--low'] || options['--info'])
        next if event.severity == 2 && !options['--all'] && (options['--critical'] || options['--high'] || options['--low'] || options['--info'])
        next if event.severity == 1 && !options['--all'] && (options['--critical'] || options['--high'] || options['--medium'] || options['--info'])
        next if event.severity == 0 && !options['--all'] && !options['--info']

        unless findings.include? event.id
          findings[event.id] = {
            :title => event.name,
            :severity => event.severity,
            :cvss => event.cvss_base_score,
            :description => event.description.strip.gsub(/[ ]+/, " "), 
            :remediation => event.solution,
            :synopsis => event.synopsis,
            :references => Array.new,
            :affected => Array.new,
            :notes => Array.new
          }
          if event.see_also
            event.see_also.each do |ref|
              findings[event.id][:references] << ref
            end
          end
          if event.cve
            event.cve.each do |cve|
              findings[event.id][:references] << "http://web.nvd.nist.gov/view/vuln/detail?vulnId=#{cve}"
            end
          end
        end

        unless findings[event.id][:affected].include? host.ip
          findings[event.id][:affected] << host.ip
        end
        
        findings[event.id][:notes] << {
          :service => "#{host.ip}:#{event.port.number}/#{event.port.protocol} (#{event.port.service})",
          :output => event.output ? event.output.strip : "<no output>"
        }
      end
    end
  end
end

# build data array ready for import

findings.each do |id, finding|
  if finding[:severity] == 4
    criticals << finding
  elsif finding[:severity] == 3
    highs << finding
  elsif finding[:severity] == 2
    mediums << finding
  elsif finding[:severity] == 1
    lows << finding
  elsif finding[:severity] == 0
    informationals << finding
  end
end

criticals = criticals.sort_by{ |k| k[:cvss] }.reverse!
highs = highs.sort_by{ |k| k[:cvss] }.reverse!
mediums = mediums.sort_by{ |k| k[:cvss] }.reverse!
lows = lows.sort_by{ |k| k[:cvss] }.reverse!
informationals = informationals.sort_by{ |k| k[:cvss] }.reverse!


# Count the number of findings for each severity level
count_criticals = criticals.length
count_highs = highs.length
count_mediums = mediums.length
count_lows = lows.length
count_informationals = informationals.length


# import data into word document template

puts "[+] Generating document #{options['--output']} ..."
puts "[+] Criticals: #{count_criticals}"
puts "[+] Highs: #{count_highs}"
puts "[+] Mediums: #{count_mediums}"
puts "[+] Lows: #{count_lows}"
puts "[+] Informationals: #{count_informationals}"

context = {
  :criticals => criticals,
  :highs => highs,
  :mediums => mediums,
  :lows => lows,
  :informationals => informationals,
  :count_criticals => count_criticals,
  :count_highs => count_highs,
  :count_mediums => count_mediums,
  :count_lows => count_lows,
  :count_informationals => count_informationals
}

template = Sablon.template(File.expand_path(File.dirname(__FILE__) + "/nessus2docx.docx"))
template.render_to_file(File.expand_path(options['--output']), context)

puts "[+] Document generation complete: #{options['--output']}"
