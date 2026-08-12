# Infrastructure providers

One sub-folder per Kubernetes infrastructure provider. Each sub-folder is owned
by its `OWNERS` (see [GOVERNANCE.md](../GOVERNANCE.md)) and contains the
provisioning methods (docs, scripts, AI skills) that prepare a cluster for
llm-d, qualified against the [conformance suite](../conformance/README.md).

| Provider | Status |
|---|---|
| [gke](gke/) | pilot provider: docs, scripts, AI skill, conformance profiles; external Terraform and AI-skill links ([accelerated-platforms](https://github.com/GoogleCloudPlatform/accelerated-platforms)) |
| [aks](aks/) | migrated docs; owners needed |
| [digitalocean](digitalocean/) | migrated docs; owners needed |
| [minikube](minikube/) | migrated docs; owners needed |
| [openshift](openshift/) | migrated docs; owners needed |
| [openshift-aws](openshift-aws/) | migrated docs; owners needed |

To add a provider (EKS, OKE, bare-metal, ...), see
[CONTRIBUTING.md](../CONTRIBUTING.md).
