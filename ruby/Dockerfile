FROM ruby:2.5

WORKDIR /usr/src/app

RUN gem install redis sinatra

COPY hello-world.rb .

EXPOSE 4567

CMD ["ruby", "/usr/src/app/hello-world.rb"]
