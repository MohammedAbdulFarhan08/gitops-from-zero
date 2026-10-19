SHELL := /bin/bash
CRD_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.PHONY: validate render diff

## validate: render every overlay and validate it, plus the ApplicationSets
validate:
	@for dir in platform-apps/overlays/*/*/; do \
		echo "→ $$dir"; \
		kustomize build "$$dir" | kubeconform -strict -summary - || exit 1; \
	done
	@echo "→ platform-apps/apps/"
	@kubeconform -strict -summary -schema-location default -schema-location '$(CRD_SCHEMAS)' platform-apps/apps/

## render: print the manifests for one app, e.g. make render ENV=prod APP=sample-app
render:
	@kustomize build platform-apps/overlays/$(ENV)/$(APP)

## diff: show how two environments differ, e.g. make diff APP=sample-app A=uat B=prod
diff:
	@diff -u <(kustomize build platform-apps/overlays/$(A)/$(APP)) <(kustomize build platform-apps/overlays/$(B)/$(APP)) || true
