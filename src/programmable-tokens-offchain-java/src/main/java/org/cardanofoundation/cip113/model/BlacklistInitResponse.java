package org.cardanofoundation.cip113.model;

public record BlacklistInitResponse(String policyId,
                                    String unsignedCborTx) {

}
