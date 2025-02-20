REPO_HUB = iconloop
NAME = prep-node
VERSION = 1910211829xc2286d
RABBITMQ_VERSION = "3.7.17"
GO_VERSION = "1.12.7"
DOCKERIZE_VERSION = "v0.6.1"
ICON_RC_VERSION="1.0.0"
DOWNLOAD_PACKAGE = "http://tbears.icon.foundation.s3-website.ap-northeast-2.amazonaws.com/docker_resource/$(VERSION)/docker_$(VERSION)_packages.tar.gz"
IS_LOCAL = true

ifdef version
VERSION = $(version)
endif

ifdef VERSION_ARG
VERSION = $(VERSION_ARG)
endif
ifdef REPO_HUB_ARG
REPO_HUB = $(REPO_HUB_ARG)
endif
ifeq ($(REPO_HUB_ARG),iconloop)
REPO_HUB = iconloop
NAME= prep-node
endif

define colorecho
      @tput setaf 6
      @echo $1
      @tput sgr0
endef

TAGNAME = $(VERSION)

NO_COLOR=\x1b[0m
OK_COLOR=\x1b[32;01m
ERROR_COLOR=\x1b[31;01m
WARN_COLOR=\x1b[33;01m
OK_STRING=$(OK_COLOR)[OK]$(NO_COLOR)
ERROR_STRING=$(ERROR_COLOR)[ERRORS]$(NO_COLOR)
WARN_STRING=$(WARN_COLOR)[WARNINGS]$(NO_COLOR)

.PHONY: all build push test tag_latest release ssh

all: build change_docker
hub: push_hub tag_latest

print_version:
	@echo "$(OK_COLOR) VERSION-> $(VERSION)  REPO-> $(REPO_HUB)/$(NAME):$(TAGNAME) $(NO_COLOR) IS_LOCAL: $(IS_LOCAL)"



make_build_args:
	@$(shell echo "$(OK_COLOR) ----- Build Environment ----- \n $(NO_COLOR)" >&2)\
	   $(shell echo "" > BUILD_ARGS) \
		$(foreach V, \
			 $(sort $(.VARIABLES)), \
			 $(if  \
				 $(filter-out environment% default automatic, $(origin $V) ), \
				 	 $($V=$($V)) \
				 $(if $(filter-out "SHELL" "%_COLOR" "%_STRING" "MAKE%" "colorecho" ".DEFAULT_GOAL" "CURDIR", "$V" ),  \
					$(shell echo '$(OK_COLOR)  $V=$(WARN_COLOR)$($V) $(NO_COLOR) ' >&2;) \
				 	$(shell echo "--build-arg $V=$($V)  " >> BUILD_ARGS)\
				  )\
			  )\
		 )

test:   make_build_args
		docker build --no-cache --rm=true -f dockerfile_test/Dockerfile  \
		$(shell cat BUILD_ARGS) \
		-t $(REPO_HUB)/$(NAME):$(TAGNAME) .

changeconfig: make_build_args
		@CONTAINER_ID=$(shell docker run -d $(REPO_HUB)/$(NAME):$(TAGNAME)) ;\
		 echo "COPY TO [$$CONTAINER_ID]" ;\
		 docker cp "src/." "$$CONTAINER_ID":/src/ ;\
		 docker exec -it "$$CONTAINER_ID" sh -c "echo `date +%Y-%m-%d:%H:%M:%S` > /.made_day" ;\
		 echo "COMMIT [$$CONTAINER_ID]" ;\
		 docker commit -m "Change the configure files `date`" "$$CONTAINER_ID" $(REPO_HUB)/$(NAME):$(TAGNAME) ;\
		 echo "STOP [$$CONTAINER_ID]" ;\
		 docker stop "$$CONTAINER_ID" ;\
		 echo "CLEAN UP [$$CONTAINER_ID]" ;\
		 docker rm "$$CONTAINER_ID"

#		-build-arg NAME=$(NAME) --build-arg APP_VERSION=$(VERSION) --build-arg DOWNLOAD_PACKAGE=$(DOWNLOAD_PACKAGE) \

build: make_build_args
		docker build --no-cache --rm=true -f centos/Dockerfile  \
		$(shell cat BUILD_ARGS) \
		-t $(REPO_HUB)/$(NAME):$(TAGNAME) .

build_python_exmq: make_build_args
		docker build --no-cache --rm=true -f python_37_exmq/Dockerfile \
		$(shell cat BUILD_ARGS) \
		-t $(REPO_HUB)/$(NAME):$(TAGNAME) .

build_python: make_build_args
		docker build --no-cache --rm=true -f python_37/Dockerfile \
		$(shell cat BUILD_ARGS) \
		-t $(REPO_HUB)/$(NAME):$(TAGNAME) .


push: print_version
		docker tag  $(NAME):$(VERSION) $(REPO_HUB)/$(NAME):$(TAGNAME)
		docker push $(REPO_HUB)/$(NAME):$(TAGNAME)

prod: print_version
		docker tag $(REPO_HUB)/$(NAME):$(TAGNAME)  $(REPO_HUB)/$(NAME):$(VERSION)
		docker push $(REPO_HUB)/$(NAME):$(VERSION)

push_hub: print_version
		#docker tag  $(NAME):$(VERSION) $(REPO_HUB)/$(NAME):$(VERSION)
		docker push $(REPO_HUB)/$(NAME):$(TAGNAME)

tag_latest: print_version
		docker tag  $(REPO_HUB)/$(NAME):$(TAGNAME) $(REPO_HUB)/$(NAME):latest
		docker push $(REPO_HUB)/$(NAME):latest

build_hub: print_version
		echo "TRIGGER_KEY" ${TRIGGERKEY}
		git add .
		git commit -m "$(NAME):$(VERSION) by Makefile"
		git tag -a "$(VERSION)" -m "$(VERSION) by Makefile"
		git push origin --tags
		curl -H "Content-Type: application/json" --data '{"build": true,"source_type": "Tag", "source_name": "$(VERSION)"}' -X POST https://registry.hub.docker.com/u/${REPO_HUB}/${NAME}/trigger/${TRIGGERKEY}/

bash: make_build_args print_version
		docker run -p 9000:9000 -p 7100:7100 -e IPADDR="20.20.1.123" -it -v $(PWD)/cert:/prep_peer/cert -v $(PWD)/data:/data -e VERSION=$(TAGNAME) -v $(PWD)/src:/src --entrypoint /bin/bash --name $(NAME) --rm $(REPO_HUB)/$(NAME):$(TAGNAME)

list:
		@echo "$(OK_COLOR) Tag List - $(REPO_HUB)/$(NAME) $(NO_COLOR)"
		@curl -s  https://registry.hub.docker.com/v1/repositories/$(REPO_HUB)/$(NAME)/tags | jq --arg REPO "$(REPO_HUB)/$(NAME):" -r '.=("\($$REPO)"+.[].name)'
		$(call colorecho, "-- END --")

change_docker:
	sed -i '' "s/$(REPO_HUB)\/$(NAME).*/$(REPO_HUB)\/$(NAME):$(VERSION)/g" docker-compose.yml

gendocs:
	@$(shell ./makeMakeDown.sh)
#	@$(foreach image, prep-node, \
#	    echo "## $(image) docker setting" >README.md ;\
#		cat src/entrypoint.sh  | grep ^export | grep -v except| cut -d "=" -f 1 | sed 's/export//g' | sed 's/_/\\_/g' | sed -e 's/^/\|/' > text1 ;\
#		cat src/entrypoint.sh | grep ^export | grep -v except | cut -d "-" -f2 | cut -d "#" -f1 | sed -e 's/[[:space:]]\*$\//'| sed -E 's/-$|}$|"//g'|sed 's/_/\\_/g' > text2 ;\
#		cat src/entrypoint.sh | grep ^export | grep -v except| cut -d "-" -f2 | cut -d "#" -f2 | sed -e 's/[[:space:]]\*$\//'| sed -E 's/-$|}$|"//g' |sed 's/_/\\_/g'|sed -e 's/$\/\|/'  > text3 ;\
#		echo "| Environment variable |Default value|  Description|" >>README.md ;\
#		echo "|--------|--------|-------|"     >>README.md ;\
#		paste -d "|" text1  text2  text3 >>README.md ;\
#		rm -f text1  text2  text3 ;\
#     )
