FROM ruby:2.5.5-stretch

RUN apt-get update && \
  apt-get -y install curl git openssh-client openssl nodejs awscli
RUN apt-get install -yq libpq-dev net-tools mysql-client wait-for-it
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

WORKDIR /opt/deimos
COPY deimos.gemspec /opt/deimos/deimos.gemspec
COPY lib/deimos/version.rb /opt/deimos/lib/deimos/version.rb
COPY Gemfile /opt/deimos/Gemfile
COPY Gemfile.lock /opt/deimos/Gemfile.lock

RUN bundle install

ADD . .

ENTRYPOINT ["bundle", "exec"]

CMD ["bundle", "exec", "rspec"]
