#!/usr/bin/env ruby
require 'rubygems'
require File.dirname(__FILE__) + '/../lib/util'
pid = File.new(File.dirname(__FILE__) + '/../tmp/dj.pid', 'w')
pid << Process.pid
pid.close
init_environment
Delayed::Worker.logger = DJ_LOGGER
Delayed::Worker.new.start  

