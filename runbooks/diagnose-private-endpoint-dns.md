# Runbook: diagnose private endpoint DNS

A client cannot reach a service over its private endpoint. Almost always DNS.
Work the steps in order, because each one eliminates a layer and the checks get
more expensive as you go down.

## The sequence

### 1. Check the virtual network's DNS servers first

Do this first. It tells you which of two different failure modes you're in, and
skipping it is how this gets misdiagnosed.

```bash
az network vnet show -g <rg> -n <vnet> --query dhcpOptions.dnsServers
```

- **Empty or null**: the virtual network uses Azure provided DNS. Linked
  private DNS zones are consulted automatically. Go to step 2.
- **A list of addresses**: the virtual network uses custom DNS, typically
  domain controllers. This is the common cause. See "Why custom DNS breaks
  this" below.

### 2. Resolve the FQDN from the client

From inside the client virtual machine, not from your laptop:

```bash
nslookup <resource>.<service-suffix>
# for example: mystorage.blob.core.windows.net
```

Read the answer, not just whether it succeeded.

### 3. A private IP came back

DNS is working. The problem is elsewhere. Move on to:

- Network security group rules on the client subnet and the private endpoint
  subnet
- Effective routes on the client network interface, particularly a default
  route pointing at a firewall that is dropping the traffic
- The service's own firewall, which is separate from anything in the network.
  Public network access set to Disabled rejects the connection at the front
  door regardless of how it was resolved

**DNS resolution and access control are independent.** The public CNAME chain
for `privatelink.<service>...` resolves from anywhere on the internet, so that
hybrid and migration scenarios keep working. A successful lookup proves the
resource exists, not that you can reach it.

### 4. A public IP came back

The private DNS zone is not being consulted for this query. Either:

- The zone is not linked to the virtual network the client is in. A zone linked
  to the hub does not serve a spoke. **Resolution follows the virtual network
  link, not the peering.** This is the most common misunderstanding: peering
  carries traffic, links carry name resolution, and they're configured
  separately.
- The zone is linked but has no A record for this resource, which happens when
  the private endpoint was created without the automatic zone group, or the
  zone name does not match the required name for that service exactly.

### 5. NXDOMAIN came back

The zone is authoritative for the namespace and has no matching record. Two
causes, and they need different fixes.

**The record is missing.** Check that the private endpoint's DNS zone group
created it.

**The name resolves to a public resource that has no private endpoint.** Once a
private DNS zone for a namespace is linked to a virtual network, that zone is
authoritative for the whole namespace from inside the network. A query for a
different resource in the same namespace, one you reach publicly and which has
no private endpoint, finds no record and returns NXDOMAIN rather than falling
through to public DNS.

Two fixes:

- Enable **fallback to internet** on the private DNS zone's virtual network
  link, which forwards unmatched queries to Azure DNS for public resolution.
  This is the maintainable option.
- Add an A record for the public IP manually. Not recommended, because nothing
  updates it when the public IP changes.

## Why custom DNS breaks this

With default settings, a virtual machine queries Azure provided DNS, which
consults private DNS zones linked to that virtual network before anything else.

Setting a custom DNS server on the virtual network replaces that resolver for
every machine in it. The custom server has no knowledge of Azure private DNS
zones, so linked zones stop being consulted. The zone and the link are fine; the
queries just never reach the resolver that would use them.

Two fixes:

- **Conditional forwarder** on the custom DNS server, for the relevant
  `privatelink.*` namespaces, pointing at `168.63.129.16`.
- **Azure DNS Private Resolver** in a linked virtual network, with the custom
  server forwarding to its inbound endpoint.

### The on premises constraint

`168.63.129.16` is a virtual public IP address reachable **only from inside an
Azure virtual network.** An on premises DNS server cannot forward to it
directly, and no amount of firewall or VPN configuration changes that.

So for on premises clients resolving private endpoints, a conditional forwarder
to `168.63.129.16` is not an available design. You need either a DNS server
running inside a virtual network that on premises forwards to, or an Azure DNS
Private Resolver inbound endpoint, which exists for this.

## Quick reference

| Symptom | Most likely cause | Fix |
|---|---|---|
| Public IP returned | Zone not linked to the client's virtual network | Add a virtual network link. Peering is not a link |
| Public IP returned, zone is linked | No A record, or zone name does not match the service's required name | Check the private endpoint's DNS zone group |
| `NXDOMAIN` | Zone is authoritative for the namespace, no matching record | Fallback to internet on the link, or add the record |
| Private IP returned, still cannot connect | Not DNS | Network security groups, routes, service firewall, public network access setting |
| Works from Azure, fails from on premises | On premises resolver cannot reach `168.63.129.16` | DNS Private Resolver inbound endpoint, or a forwarder virtual machine in a virtual network |
