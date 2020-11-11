CURL:=/usr/bin/curl --netrc --silent
PROJECT=dashboard
GITHUB_API_BASE:=https://api.github.com/repos/$(GITHUB_USER)/$(PROJECT)/pages

build: ## build the site
	perl dashboard

publish: build ## build the site and send to GitHub
	git commit -a -m 'Publish site'
	git push

# https://developer.github.com/v3/repos/pages/
.PHONY: status
status: guard-GITHUB_USER ## show the GitHub Pages build status
	@ $(CURL) -H "Accept: application/vnd.github.v3+json" $(GITHUB_API_BASE) | jq -r .status

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

######################################################################
# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help ## Show all the Makefile targets with descriptions
help: ## show a list of targets
	@grep -E '^[a-zA-Z][/a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
