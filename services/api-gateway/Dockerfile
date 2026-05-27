FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install -y \
      build-essential \
      libpq-dev \
      libyaml-dev \
      libffi-dev \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem update --system && \
    gem install bundler && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

COPY . .

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
