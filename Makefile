VAGRANT := vagrant
VM  := p3

RM      := rm -rf

.DEFAULT_GOAL := help

.PHONY: help up provision ssh status destroy clean kubeconfig get-nodes logs

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ────────────────────────────────────────────────────────────────────────────────
# Vagrant lifecycle
# ────────────────────────────────────────────────────────────────────────────────

up: ## Start VM
	$(VAGRANT) up

provision: ## Re-run provisioning on all machines
	$(VAGRANT) provision

status: ## Show status of all machines
	$(VAGRANT) status

destroy: ## Destroy all VMs (use with caution!)
	$(VAGRANT) destroy -f
	$(RM) .vagrant

re: destroy up ## Recreate VMs from scratch (use with caution!)

clean: destroy ## Alias for destroy

halt: ## Stop (suspend) all running VMs
	$(VAGRANT) halt

reload: ## Reload VMs (useful after config changes)
	$(VAGRANT) reload --provision

reload-scale-up: ## Scale up VM resources to 4GB RAM and 4 CPUs, then reload
	VAGRANT_RAM=4096 VAGRANT_CPU=4 $(VAGRANT) reload --provision

reload-scale-down: ## Scale down VM resources to 2GB RAM and 2 CPUs, then reload
	VAGRANT_RAM=2048 VAGRANT_CPU=2 $(VAGRANT) reload --provision

# ────────────────────────────────────────────────────────────────────────────────
# Access & debug
# ────────────────────────────────────────────────────────────────────────────────

ssh: ## SSH into the VM
	$(VAGRANT) ssh $(VM)

logs: ## Show recent K3s server logs from VM
	$(VAGRANT) ssh $(VM) -- "sudo journalctl -u k3s -n 100 --no-pager"
