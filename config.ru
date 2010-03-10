require 'rubygems'
require 'sinatra'
require 'linked_lccn'
Sinatra::Application.default_options.merge!(
  :run => false,
  :env => :production,
  :raise_errors => true
)
 
log = File.new("sinatra.log", "a")
STDOUT.reopen(log)
STDERR.reopen(log)

run Sinatra::Application