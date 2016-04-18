FROM ruby:2.3.0

RUN gem install bundler
RUN bundle config --global frozen 1

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY ./Gemfile /usr/src/app/Gemfile
COPY ./Gemfile.lock /usr/src/app/Gemfile.lock

RUN bundle install --jobs=20

COPY . /usr/src/app

EXPOSE 3000

CMD ["bundle","exec","unicorn","-E","production","-c","./config/unicorn.rb"]
