{{- $ASN := .ASN -}}{{- $RouterId := .Loopback -}}! The frr version is not rendered since it seems to be optional.
frr defaults datacenter
# This is the only line changed from upstream: https://github.com/metal-stack/metal-core/blob/master/cmd/internal/switcher/templates/tpl/sonic_frr.tpl
# Follow-up issue: https://github.com/metal-stack/metal-core/issues/199
fpm address 127.0.0.1
hostname {{ .Name }}
password zebra
enable password zebra
!
agentx
log syslog {{ .LogLevel }}
log facility local4
debug bgp updates
debug bgp nht
debug bgp update-groups
debug bgp zebra
debug zebra events
debug zebra nexthop detail
debug zebra rib detailed
debug zebra nht detailed
{{- range $vrf, $t := .Ports.Vrfs }}
!
vrf Vrf{{ $t.VNI }}
 vni {{ $t.VNI }}
 exit-vrf
{{- end }}
{{- range .Ports.Underlay }}
!
interface {{ . }}
 ipv6 nd ra-interval 6
 no ipv6 nd suppress-ra
{{- end }}
{{- range .Ports.Firewalls }}
!
interface {{ .Port }}
 ipv6 nd ra-interval 6
 no ipv6 nd suppress-ra
{{- end }}
{{- range $vrf, $t := .Ports.Vrfs }}
{{- range $t.Neighbors }}
!
interface {{ . }} vrf {{ $vrf }}
 ipv6 nd ra-interval 6
 no ipv6 nd suppress-ra
{{- end }}
{{- end }}
!
router bgp {{ $ASN }}
 bgp router-id {{ $RouterId }}
 bgp bestpath as-path multipath-relax
 neighbor FABRIC peer-group
 neighbor FABRIC remote-as external
 neighbor FABRIC timers 2 8
 {{- range .Ports.Underlay }}
 neighbor {{ . }} interface peer-group FABRIC
 {{- end }}
 neighbor FIREWALL peer-group
 neighbor FIREWALL remote-as external
 neighbor FIREWALL timers 2 8
 {{- range .Ports.Firewalls }}
 neighbor {{ .Port }} interface peer-group FIREWALL
 {{- end }}
 !
 address-family ipv4 unicast
  redistribute connected route-map DENY_MGMT
  redistribute kernel route-map DENY_MGMT
  neighbor FIREWALL allowas-in 2
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-in in
  {{- end }}
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute connected route-map DENY_MGMT
  redistribute kernel route-map DENY_MGMT
  neighbor FIREWALL allowas-in 2
  # see https://docs.frrouting.org/en/latest/bgp.html#clicmd-neighbor-A.B.C.D-activate
  # why activate is required
  neighbor FIREWALL activate
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-in in
  {{- end }}
 exit-address-family
 !
 address-family l2vpn evpn
  advertise-all-vni
  neighbor FABRIC activate
  neighbor FABRIC allowas-in 2
  neighbor FIREWALL activate
  neighbor FIREWALL allowas-in 2
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-vni out
  {{- end }}
 exit-address-family
!
route-map DENY_MGMT deny 10
  match interface eth0
route-map DENY_MGMT permit 20
!
{{- range $k, $f := .Ports.Firewalls }}
# route-maps for firewall@{{ $k }}
        {{- range $f.IPPrefixLists }}
ip prefix-list {{ .Name }} {{ .Spec }}
        {{- end}}
        {{- range $f.RouteMaps }}
route-map {{ .Name }} {{ .Policy }} {{ .Order }}
                {{- range .Entries }}
 {{ . }}
                {{- end }}
        {{- end }}
!
{{- end }}
{{- if .Ports.Eth0.Gateway }}
ip route 0.0.0.0/0 {{ .Ports.Eth0.Gateway }} nexthop-vrf mgmt
{{- end }}
!
{{- range $vrf, $t := .Ports.Vrfs }}
router bgp {{ $ASN }} vrf {{ $vrf }}
 bgp router-id {{ $RouterId }}
 bgp bestpath as-path multipath-relax
 neighbor MACHINE peer-group
 neighbor MACHINE remote-as external
 neighbor MACHINE timers 2 8
 {{- range $t.Neighbors }}
 neighbor {{ . }} interface peer-group MACHINE
 {{- end }}
 !
 {{- if $t.Has4 }}
 address-family ipv4 unicast
  redistribute connected
  neighbor MACHINE maximum-prefix 24000
  {{- if gt (len $t.IPPrefixLists) 0 }}
  neighbor MACHINE route-map {{ $vrf }}-in in
  {{- end }}
 exit-address-family
 !
 {{- end }}
 {{- if $t.Has6 }}
 address-family ipv6 unicast
  redistribute connected
  neighbor MACHINE maximum-prefix 24000
  # see https://docs.frrouting.org/en/latest/bgp.html#clicmd-neighbor-A.B.C.D-activate
  # why activate is required
  neighbor MACHINE activate
  {{- if gt (len $t.IPPrefixLists) 0 }}
  neighbor MACHINE route-map {{ $vrf }}-in6 in
  {{- end }}
 exit-address-family
 !
 {{- end }}
 address-family l2vpn evpn
 {{- if $t.Has4 }}
  advertise ipv4 unicast
 {{- end }}
 {{- if $t.Has6 }}
  advertise ipv6 unicast
 {{- end }}
 exit-address-family
!
{{- if gt (len $t.IPPrefixLists) 0 }}
# route-maps for {{ $vrf }}
        {{- range $t.IPPrefixLists }}
ip prefix-list {{ .Name }} {{ .Spec }}
        {{- end}}
        {{- range $t.RouteMaps }}
route-map {{ .Name }} {{ .Policy }} {{ .Order }}
                {{- range .Entries }}
 {{ . }}
                {{- end }}
        {{- end }}
!{{- end }}{{- end }}
{{- if .SetSrcLoopback }}
route-map RM_SET_SRC permit 10
 set src {{ .Loopback }}
exit
!
ip protocol bgp route-map RM_SET_SRC
!
{{- end }}
line vty
!
