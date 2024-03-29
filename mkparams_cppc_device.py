import sys
import re
def showandexit_usage(code=1):
    print("Usage:", file=sys.stderr)
    print("python mkparams_cppc_device.py <mode>", file=sys.stderr)
    print(" --smt <nthreads_per_core=2>", file=sys.stderr)
    print(" [--offset_highestperf {<host thread id min>..<host thread id max>=<offset>,}]", file=sys.stderr)
    print(" --vcpu_assignment {<vcpu id>:<host thread id>,}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Generates a configuration for the QEMU CPPC device based on the current host CPPC values.", file=sys.stderr)
    print("Modes:", file=sys.stderr)
    print("  preview - Preview the mapping from vcpu to CPPC highest_perf values", file=sys.stderr)
    print("  config_qemu - Output qemu command line arguments for the CPPC device", file=sys.stderr)
    print("  config_libvirt - Output libvirt xml 'commandline' entries, see libvirt docs: https://www.libvirt.org/kbase/qemu-passthrough-security.html", file=sys.stderr)
    print("Options:", file=sys.stderr)
    print("  --smt <arg=2> - The number of threads (consecutive vCPU IDs) per virtual core in the VM topology. Usually 2 or 1.", file=sys.stderr)
    print("  --offset_highestperf <arg> - A comma-separated list of host CPU thread ranges with corresponding CPPC highest_perf offsets: \"<min host cpu>..<max>=<offset>\"", file=sys.stderr)
    print("  --vcpu_assignment <arg> - A comma-separated list of guest-to-host thread ID mappings : \"<vcpu id>:<host thread id>\" matching the VM's pinning settings.", file=sys.stderr)
    print("", file=sys.stderr)
    print("Example for a Ryzen 7950X3D with offsets to prefer the V-Cache cores (host threads 0..7 and 16..23):", file=sys.stderr)
    print("python mkparams_cppc_device.py config_libvirt --smt 2 --offset_highestperf 0..7=+40,8..15=-40,16..23=+40,24..31=-40 --vcpu_assignment 0:4,1:20,<etc. for all 32 threads>", file=sys.stderr)
    print("Note: The highest_perf numbers should remain in [0..255] with the offsets applied.", file=sys.stderr)
    sys.exit(code)

if len(sys.argv) < 2:
    showandexit_usage()
mode = sys.argv[1]
if mode not in {"preview", "config_qemu", "config_libvirt"}:
    print("Unknown mode value.", file=sys.stderr)
    showandexit_usage()

nthreads_per_core = 2
offsetval = []
physcpu_by_vcpu = {}

i_arg = 2
while i_arg < len(sys.argv):
    opt=sys.argv[i_arg]
    i_arg+=1
    if i_arg >= len(sys.argv):
        print("Missing argument value.", file=sys.stderr)
        showandexit_usage()
    if opt == "--smt":
        nthreads_per_core = int(sys.argv[i_arg])
        i_arg+=1
    elif opt == "--offset_highestperf":
        arg=sys.argv[i_arg]
        i_arg+=1
        
        re_pattern = re.compile(r'^(\d+)..(\d+)=([\+\-]?\d+)$')
        offsets_matches = [re_pattern.match(entry) for entry in arg.split(',') if len(entry)>0]
        if any((True for match in offsets_matches if match is None)):
            print("offset_highestperf parsing error.", file=sys.stderr)
            showandexit_usage()
        offsetval += [(int(match.group(1)), int(match.group(2)), int(match.group(3))) for match in offsets_matches]
    elif opt == "--vcpu_assignment":
        arg=sys.argv[i_arg]
        i_arg+=1
        
        re_pattern = re.compile(r'^(\d+):(\d+)$')
        assignment_matches = [re_pattern.match(entry) for entry in arg.split(',') if len(entry)>0]
        if any((True for match in assignment_matches if match is None)):
            print("vcpu_assignment parsing error.", file=sys.stderr)
            showandexit_usage()
        physcpu_by_vcpu.update({int(match.group(1)):int(match.group(2)) for match in assignment_matches})

if len(physcpu_by_vcpu) == 0:
    print("Missing vCPU assignments.", file=sys.stderr)
    showandexit_usage()
if len(physcpu_by_vcpu) % nthreads_per_core > 0:
    print("Missing vCPU assignments (count not divisible by smt).", file=sys.stderr)
    sys.exit(1)

def apply_perf_offsets(physcpu, perf):
    for offs_tpl in offsetval:
        if physcpu >= offs_tpl[0] and physcpu <= offs_tpl[1]:
            return perf + offs_tpl[2]
    return perf
        
# Assumes that each core's SMTs are assigned to neighboring vCPUs.
# (-> QEMU sources: include/hw/i386/topology.h)

def cppc_readf(i_cpu, name):
    with open('/sys/devices/system/cpu/cpu%d/acpi_cppc/%s' % (i_cpu, name), 'r') as f:
        return f.readline().rstrip('\n')

def iter_cpu_mappings(handler):
    for vcpu in physcpu_by_vcpu:
        physcpu = physcpu_by_vcpu[vcpu]
        is_nonprimary_smt = (vcpu % nthreads_per_core) != 0
        vcpu_primary_smt = vcpu - (vcpu % nthreads_per_core)
        handler(vcpu, vcpu_primary_smt, physcpu,
               "%d" % apply_perf_offsets(physcpu, int(cppc_readf(physcpu, 'highest_perf'))),
               cppc_readf(physcpu, 'nominal_perf'),
               cppc_readf(physcpu, 'lowest_nonlinear_perf'),
               cppc_readf(physcpu, 'lowest_perf'))

if mode == "preview":
    def addto_preview(vcpu, vcpu_primary_smt, physcpu, highest_perf, nominal_perf, lowest_nonlinear_perf, lowest_perf):
        print("vCPU %2d (host thread %2d): highest_perf %s, nominal_perf %s, lowest_nonlinear_perf %s, lowest_perf %s" % (vcpu, physcpu, highest_perf, nominal_perf, lowest_nonlinear_perf, lowest_perf))
    iter_cpu_mappings(addto_preview)
elif mode == "config_qemu" or mode == "config_libvirt":
    processors_arr = []
    def addto_qemu(vcpu, vcpu_primary_smt, physcpu, highest_perf, nominal_perf, lowest_nonlinear_perf, lowest_perf):
        processors_arr.append("\"%d:%d:%s:%s:%s:%s\"" % (vcpu, vcpu_primary_smt, highest_perf, nominal_perf, lowest_nonlinear_perf, lowest_perf))
    iter_cpu_mappings(addto_qemu)
    device_str = '{"driver":"acpi-cppc","processors":[' + ','.join(processors_arr) + ']}'
    
    if mode == "config_qemu":
        print('-device \'' + device_str + '\'')
    else: #config_libvirt
        def xml_escape(val):
            val_out = ''
            for i in range(len(val)):
                if val[i] == '"':
                    val_out += '&quot;'
                elif val[i] == "'":
                    val_out += '&apos;'
                elif val[i] == "<":
                    val_out += '&lt;'
                elif val[i] == ">":
                    val_out += '&gt;'
                elif val[i] == "&":
                    val_out += '&amp;'
                else:
                    val_out += val[i]
            return val_out
        print('<qemu:arg value="-device"/>')
        print('<qemu:arg value="' + xml_escape(device_str) + '"/>')
