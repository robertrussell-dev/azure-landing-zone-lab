# Deliberately non compliant resources, created on purpose.
#
# Read this before assuming it is a mistake.
#
# The brownfield adoption pattern in ADR 0005 only demonstrates anything if the
# adopted subscription actually violates the policies it is being measured
# against. An empty subscription reports no compliance state at all, because
# there is nothing to evaluate, which makes the audit only assignment look like
# it is not working when it is simply not applicable to anything.
#
# In a real engagement these violations already exist and nobody had to create
# them. Here they are seeded, and the README says so rather than implying an
# inherited mess.
#
# Everything below is free. Virtual networks, subnets and network security
# groups carry no hourly charge.
#
# A second violation used to live here: a network interface carrying a public
# IP, which tripped the Deny assigned at Corp. Because this subscription sits
# under Corp (audit only) it was created successfully and recorded as non
# compliant, where under Corp the same call is refused. That is the clearest
# demonstration in this platform of enforcement following placement rather than
# policy.
#
# It was removed after the compliance evidence was captured, because a Standard
# static public IP is the only resource here that bills by the hour. The
# evidence is committed at docs/evidence/policy-portal.png. This is the deploy,
# screenshot, destroy discipline the network stack uses, applied to a single
# resource.

# ---------------------------------------------------------------------------
# Who owns the costCenter tag
# ---------------------------------------------------------------------------
# The Modify assignment at the intermediate root appends costCenter to any
# resource created without it. It works: nothing below declares costCenter, and
# every resource here carries costCenter = lab after creation.
#
# That creates a fight. Terraform reads the tag back, does not find it in the
# configuration, and plans to remove it. Applying that removal triggers the
# Modify effect again on the next write, which puts the tag back. The result is
# a plan that is never clean and a pipeline that reports drift forever.
#
# The fix is to decide who owns the field and say so. Azure Policy owns
# costCenter, so Terraform ignores it. The alternative, declaring the tag in
# every resource, means the policy never has anything to do and its compliance
# reporting becomes meaningless.
#
# This applies to every Modify assignment in an estate, not just to this file.
# It is the practical cost of policy driven governance alongside infrastructure
# as code, and it is why Modify assignments should be few and well known.

resource "azurerm_resource_group" "seed" {
  provider = azurerm.brownfield

  name     = "rg-legacy-app"
  location = var.location

  # Deliberately missing costCenter. The Modify assignment at the intermediate
  # root appends it to resources that lack it, so this is also the test of
  # whether that assignment does what it claims.
  tags = {
    autoDelete = "true"
  }
}

# Violation 1: a subnet with no network security group attached.
#
# Trips "Subnets should be associated with a Network Security Group", assigned
# as AuditIfNotExists at the intermediate root. Reports, never blocks, so this
# is non compliant everywhere in the hierarchy rather than only under the audit
# only archetype.
resource "azurerm_virtual_network" "seed" {
  provider = azurerm.brownfield

  name                = "vnet-legacy-app"
  resource_group_name = azurerm_resource_group.seed.name
  location            = azurerm_resource_group.seed.location
  address_space       = ["10.240.0.0/24"]

  tags = {
    autoDelete = "true"
  }

  lifecycle {
    # Azure Policy owns costCenter. See the note above.
    ignore_changes = [tags["costCenter"]]
  }
}

resource "azurerm_subnet" "no_nsg" {
  provider = azurerm.brownfield

  # checkov:skip=CKV2_AZURE_31:This subnet has no network security group on
  # purpose. It exists to make the AuditIfNotExists assignment at the
  # intermediate root report a real finding. Attaching one would remove the
  # only thing this resource is here to demonstrate.

  name                 = "snet-no-nsg"
  resource_group_name  = azurerm_resource_group.seed.name
  virtual_network_name = azurerm_virtual_network.seed.name
  address_prefixes     = ["10.240.0.0/26"]

  # No network_security_group_association resource, on purpose. That absence is
  # the whole point of this file.
}
