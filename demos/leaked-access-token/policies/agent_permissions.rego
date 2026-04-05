package demo.agents

import rego.v1

# Agent capability mappings for the CTF demo
#
# Claude is restricted to engineering ONLY.
# Even though Alex (the user) has ["engineering", "hr"],
# the intersection will be ["engineering"] — blocking HR access.

agent_capabilities := {
    "claude-agent": ["engineering"],
}

has_capability(agent_name, department) if {
    capability_list := agent_capabilities[agent_name]
    department in capability_list
}

get_capabilities(agent_name) := capabilities if {
    capabilities := agent_capabilities[agent_name]
}

get_capabilities(agent_name) := [] if {
    not agent_capabilities[agent_name]
}
