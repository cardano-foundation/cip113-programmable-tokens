package org.cardanofoundation.cip113.model;

import java.util.List;

public record RegistryNodes(ProtocolParams protocolParams, List<RegistryNode> registryNodes) {
}
