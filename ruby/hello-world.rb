require 'sinatra'
require 'redis'

class HelloWorld < Sinatra::Base

  redis = Redis.new(:host => ENV["REDIS_HOST"] || "127.0.0.1" , :port => ENV["REDIS_PORT"] || 6379)

  get '/' do
    redis.ping
    "Hello World!"
  end

end
