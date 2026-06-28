FROM ruby:3.4-alpine AS base

RUN apk add --no-cache \
    postgresql-client \
    postgresql-dev \
    build-base \
    tzdata \
    git \
    curl \
    libc-dev

WORKDIR /app

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development

FROM base AS build

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY . .
RUN bundle exec rails assets:precompile 2>/dev/null || true

FROM base AS final

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN addgroup -S rails && adduser -S rails -G rails
RUN chown -R rails:rails /app
USER rails

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/healthcheck || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
