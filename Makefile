# Makefile

.PHONY lint test serve

lint:
	@bundle exec rubocop --fail-level warning --display-only-fail-level-offenses

test:
	@bundle exec rake test

serve:
	@foreman start
