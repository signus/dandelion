# Dockerfile

FROM ruby:3.2.3
ENV INSTALL_PATH /opt/app

RUN apt update -y
RUN apt install -y libssl-dev libreadline-dev zlib1g-dev autoconf bison build-essential libyaml-dev libreadline-dev libncurses5-dev libffi-dev libgdbm-dev openssl

RUN mkdir -p $INSTALL_PATH

COPY . $INSTALL_PATH
WORKDIR $INSTALL_PATH
RUN bundle config path vendor/bundle
RUN bundle install --jobs 4 --retry 3
RUN gem install foreman

ENV RACK_ENV development
CMD [ "foreman", "start" ]
