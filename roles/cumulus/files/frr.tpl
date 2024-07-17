{{- $ASN := .ASN -}}{{- $RouterId := .Loopback -}}! The frr version is not rendered since it seems to be optional.
frr defaults datacenter
hostname {{ .Name }}
username cumulus nopassword
service integrated-vtysh-config
!
log syslog {{ .LogLevel }}
debug bgp updates
debug bgp nht
debug bgp update-groups
debug bgp zebra
!
vrf vrfInternet
 vni 104009
 ip route 0.0.0.0/0 172.17.0.1 nexthop-vrf mgmt
exit-vrf
vrf vrfInternet6
 vni 106009
 ip route ::/0 2001:db8:1::1 nexthop-vrf mgmt
exit-vrf
{{- range $vrf, $t := .Ports.Vrfs }}
!
vrf vrf{{ $t.VNI }}
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
 neighbor FABRIC timers 1 3
 {{- range .Ports.Underlay }}
 neighbor {{ . }} interface peer-group FABRIC
 {{- end }}
 neighbor FIREWALL peer-group
 neighbor FIREWALL remote-as external
 neighbor FIREWALL timers 1 3
 {{- range .Ports.Firewalls }}
 neighbor {{ .Port }} interface peer-group FIREWALL
 {{- end }}
 !
 address-family ipv4 unicast
  redistribute connected route-map LOOPBACKS
  neighbor FIREWALL allowas-in 1
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-in in
  {{- end }}
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute connected route-map LOOPBACKS
  neighbor FIREWALL allowas-in 2
  neighbor FIREWALL activate
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-in in
  {{- end }}
 exit-address-family
 !
 address-family l2vpn evpn
  advertise-all-vni
  neighbor FABRIC activate
  neighbor FIREWALL activate
  neighbor FIREWALL allowas-in 1
  {{- range $k, $f := .Ports.Firewalls }}
  neighbor {{ $f.Port }} route-map fw-{{ $k }}-vni out
  {{- end }}
 exit-address-family
!
route-map LOOPBACKS permit 10
 match interface lo
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
ip route 0.0.0.0/0 {{ .Ports.Eth0.Gateway }} nexthop-vrf mgmt
!
{{- range $vrf, $t := .Ports.Vrfs }}
router bgp {{ $ASN }} vrf {{ $vrf }}
 bgp router-id {{ $RouterId }}
 bgp bestpath as-path multipath-relax
 neighbor MACHINE peer-group
 neighbor MACHINE remote-as external
 neighbor MACHINE timers 1 3
 {{- range $t.Neighbors }}
 neighbor {{ . }} interface peer-group MACHINE
 {{- end }}
 !
 address-family ipv4 unicast
  redistribute connected
  neighbor MACHINE maximum-prefix 24000
  {{- if gt (len $t.IPPrefixLists) 0 }}
  neighbor MACHINE route-map {{ $vrf }}-in in
  {{- end }}
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute connected
  neighbor MACHINE maximum-prefix 24000
  neighbor MACHINE activate
  {{- if gt (len $t.IPPrefixLists) 0 }}
  neighbor MACHINE route-map {{ $vrf }}-in6 in
  {{- end }}
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast
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
!
router bgp {{ $ASN }} vrf vrfInternet
 bgp router-id {{ $RouterId }}
 bgp bestpath as-path multipath-relax
 !
 address-family ipv4 unicast
  import vrf mgmt
  network 0.0.0.0/0
 exit-address-family
 !
 address-family ipv6 unicast
  import vrf mgmt
  network ::/0
 exit-address-family
 !
 address-family l2vpn evpn
  advertise ipv4 unicast
 exit-address-family
!
vrf mgmt
 ip route 10.0.1.0/24 {{ .Loopback }} nexthop-vrf default
 ip route 100.255.254.0/24 vrfInternet nexthop-vrf vrfInternet
exit-vrf
!
line vty
!