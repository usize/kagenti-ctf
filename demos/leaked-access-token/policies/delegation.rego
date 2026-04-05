package demo.authorization

import rego.v1

import data.demo.agents
import data.demo.users

# Core authorization logic: permission intersection
#
# When an agent acts on behalf of a user:
#   Effective Permissions = User Departments ∩ Agent Capabilities
#
# For this CTF demo:
#   Alex's departments:     ["engineering", "hr"]
#   Claude's capabilities:  ["engineering"]
#   Intersection:           ["engineering"]
#   HR documents require:   "hr"
#   Result:                 DENIED

parse_spiffe_id(spiffe_id) := result if {
    parts := split(spiffe_id, "/")
    count(parts) >= 2
    result := {"type": parts[count(parts) - 2], "name": parts[count(parts) - 1]}
}

get_required_departments := deps if {
    deps := input.document_metadata.required_departments
} else := [dep] if {
    dep := input.document_metadata.required_department
    dep != ""
} else := []

is_public_document if {
    required := get_required_departments
    count(required) == 0
}

has_any_required_department(permissions) if {
    is_public_document
}

has_any_required_department(permissions) if {
    required := get_required_departments
    some dept in required
    dept in permissions
}

default allow := false

# Rule 1: Public documents are always accessible
allow if {
    is_public_document
}

# Rule 2: Direct user access via SPIFFE ID (no agent delegation)
allow if {
    not input.delegation
    caller := parse_spiffe_id(input.caller_spiffe_id)
    caller.type == "user"
    user_depts := users.get_departments(caller.name)
    has_any_required_department(user_depts)
}

# Rule 2b: Direct JWT access (non-SPIFFE caller with groups from token)
allow if {
    not input.delegation
    not parse_spiffe_id(input.caller_spiffe_id)
    input.user_departments
    count(input.user_departments) > 0
    has_any_required_department(input.user_departments)
}

# Rule 2c: Agent calling with user's groups (AuthBridge token exchange)
# After token exchange, the token has azp=agent SPIFFE ID and groups
# from the original user. Compute: user_departments ∩ agent_capabilities
allow if {
    not input.delegation
    caller := parse_spiffe_id(input.caller_spiffe_id)
    caller.type == "sa"
    input.user_departments
    count(input.user_departments) > 0
    agent_caps := agents.get_capabilities(caller.name)
    effective := {d | some d in input.user_departments; d in agent_caps}
    has_any_required_department(effective)
}

# Rule 3: Delegated access (user delegates to agent)
allow if {
    input.delegation
    user := parse_spiffe_id(input.delegation.user_spiffe_id)
    agent := parse_spiffe_id(input.delegation.agent_spiffe_id)
    user.type == "user"
    agent.type == "agent"
    user_depts := users.get_departments(user.name)
    agent_caps := agents.get_capabilities(agent.name)
    effective := {d | some d in user_depts; d in agent_caps}
    has_any_required_department(effective)
}

# Rule 3b: Delegated JWT access (azp is agent SPIFFE ID, sub is user UUID)
allow if {
    input.delegation
    agent_id := input.delegation.agent_spiffe_id
    agent := parse_spiffe_id(agent_id)
    user_depts := input.delegation.user_departments
    count(user_depts) > 0
    agent_caps := agents.get_capabilities(agent.name)
    effective := {d | some d in user_depts; d in agent_caps}
    has_any_required_department(effective)
}

deny_reason := "Agent requests require user delegation context" if {
    not input.delegation
    caller := parse_spiffe_id(input.caller_spiffe_id)
    caller.type == "agent"
}

# Effective permissions via SPIFFE ID lookup
effective_permissions := result if {
    input.delegation
    user := parse_spiffe_id(input.delegation.user_spiffe_id)
    agent := parse_spiffe_id(input.delegation.agent_spiffe_id)
    user_depts := users.get_departments(user.name)
    agent_caps := agents.get_capabilities(agent.name)
    result := [d | some d in user_depts; d in agent_caps]
}

# Effective permissions via JWT claims (delegation with user_departments)
effective_permissions := result if {
    input.delegation
    not parse_spiffe_id(input.delegation.user_spiffe_id)
    agent := parse_spiffe_id(input.delegation.agent_spiffe_id)
    user_depts := input.delegation.user_departments
    agent_caps := agents.get_capabilities(agent.name)
    result := [d | some d in user_depts; d in agent_caps]
}

decision := {"allow": allow, "reason": reason, "details": details}

reason := "Public document accessible to all" if {
    allow
    is_public_document
}

reason := "User has required department access" if {
    allow
    not input.delegation
    not is_public_document
}

reason := "Both user and agent have required access (delegation)" if {
    allow
    input.delegation
    not is_public_document
}

reason := deny_reason if {
    not allow
    deny_reason
}

reason := "Insufficient permissions" if {
    not allow
    not deny_reason
}

details := {
    "document_id": input.document_id,
    "required_departments": get_required_departments,
    "caller": input.caller_spiffe_id
} if {
    not input.delegation
}

details := {
    "document_id": input.document_id,
    "required_departments": get_required_departments,
    "delegation": input.delegation,
    "effective_permissions": effective_permissions
} if {
    input.delegation
}
