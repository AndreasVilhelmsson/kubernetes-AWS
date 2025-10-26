# Security group rule för inter-node communication
# Tillåter all trafik mellan worker nodes (för pod-to-pod communication)

resource "aws_security_group_rule" "node_to_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = module.eks.node_security_group_id
  description              = "Allow all traffic between worker nodes"
}
