import 'package:json_annotation/json_annotation.dart';

part 'payment_models.g.dart';

enum PaymentStatus {
  pending,
  completed,
  failed,
  cancelled,
  refunded;

  static PaymentStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return PaymentStatus.pending;
      case 'completed':
        return PaymentStatus.completed;
      case 'failed':
        return PaymentStatus.failed;
      case 'cancelled':
        return PaymentStatus.cancelled;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }
}

enum PaymentGateway {
  stripe,
  paypal,
  iap; // In-App Purchase

  static PaymentGateway fromString(String gateway) {
    switch (gateway.toLowerCase()) {
      case 'stripe':
        return PaymentGateway.stripe;
      case 'paypal':
        return PaymentGateway.paypal;
      case 'iap':
        return PaymentGateway.iap;
      default:
        return PaymentGateway.iap;
    }
  }
}

@JsonSerializable()
class PaymentTransaction {
  final String id;
  final String productId;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final PaymentGateway gateway;
  final String? gatewayTransactionId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? userId;
  final Map<String, dynamic>? metadata;
  final bool isTest;

  PaymentTransaction({
    required this.id,
    required this.productId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.gateway,
    this.gatewayTransactionId,
    required this.createdAt,
    this.updatedAt,
    this.userId,
    this.metadata,
    this.isTest = false,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      _$PaymentTransactionFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentTransactionToJson(this);

  PaymentTransaction copyWith({
    String? id,
    String? productId,
    double? amount,
    String? currency,
    PaymentStatus? status,
    PaymentGateway? gateway,
    String? gatewayTransactionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
    Map<String, dynamic>? metadata,
    bool? isTest,
  }) {
    return PaymentTransaction(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      gateway: gateway ?? this.gateway,
      gatewayTransactionId: gatewayTransactionId ?? this.gatewayTransactionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
      metadata: metadata ?? this.metadata,
      isTest: isTest ?? this.isTest,
    );
  }
}

@JsonSerializable()
class PaymentResult {
  final bool success;
  final String? transactionId;
  final String? gatewayTransactionId;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;

  PaymentResult({
    required this.success,
    this.transactionId,
    this.gatewayTransactionId,
    this.message,
    this.error,
    this.data,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) =>
      _$PaymentResultFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentResultToJson(this);
}

@JsonSerializable()
class PaymentReceipt {
  final String id;
  final String transactionId;
  final String receiptNumber;
  final String productName;
  final double amount;
  final String currency;
  final PaymentStatus status;
  final PaymentGateway gateway;
  final DateTime issuedAt;
  final String? downloadUrl;
  final Map<String, dynamic>? details;
  final ReceiptCustomer customer;
  final ReceiptVendor vendor;

  PaymentReceipt({
    required this.id,
    required this.transactionId,
    required this.receiptNumber,
    required this.productName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.gateway,
    required this.issuedAt,
    this.downloadUrl,
    this.details,
    required this.customer,
    required this.vendor,
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) =>
      _$PaymentReceiptFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentReceiptToJson(this);
}

@JsonSerializable()
class ReceiptCustomer {
  final String? name;
  final String? email;
  final String? address;
  final String? city;
  final String? country;
  final String? postalCode;

  ReceiptCustomer({
    this.name,
    this.email,
    this.address,
    this.city,
    this.country,
    this.postalCode,
  });

  factory ReceiptCustomer.fromJson(Map<String, dynamic> json) =>
      _$ReceiptCustomerFromJson(json);

  Map<String, dynamic> toJson() => _$ReceiptCustomerToJson(this);
}

@JsonSerializable()
class ReceiptVendor {
  final String name;
  final String address;
  final String city;
  final String country;
  final String postalCode;
  final String? taxId;
  final String? email;
  final String? phone;

  ReceiptVendor({
    required this.name,
    required this.address,
    required this.city,
    required this.country,
    required this.postalCode,
    this.taxId,
    this.email,
    this.phone,
  });

  factory ReceiptVendor.fromJson(Map<String, dynamic> json) =>
      _$ReceiptVendorFromJson(json);

  Map<String, dynamic> toJson() => _$ReceiptVendorToJson(this);
}

@JsonSerializable()
class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String duration; // monthly, yearly, weekly
  final List<String> features;
  final bool isPopular;
  final String? originalPrice;
  final int? discountPercentage;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.duration,
    required this.features,
    this.isPopular = false,
    this.originalPrice,
    this.discountPercentage,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionPlanFromJson(json);

  Map<String, dynamic> toJson() => _$SubscriptionPlanToJson(this);
}

@JsonSerializable()
class UserSubscription {
  final String id;
  final String userId;
  final String planId;
  final PaymentStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final bool autoRenew;
  final PaymentGateway gateway;
  final String? gatewaySubscriptionId;
  final DateTime? nextBillingDate;
  final SubscriptionPlan? plan;

  UserSubscription({
    required this.id,
    required this.userId,
    required this.planId,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
    required this.gateway,
    this.gatewaySubscriptionId,
    this.nextBillingDate,
    this.plan,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) =>
      _$UserSubscriptionFromJson(json);

  Map<String, dynamic> toJson() => _$UserSubscriptionToJson(this);

  bool get isActive {
    final now = DateTime.now();
    return status == PaymentStatus.completed &&
        startDate.isBefore(now) &&
        endDate.isAfter(now);
  }

  bool get isExpired {
    return DateTime.now().isAfter(endDate);
  }

  Duration get timeRemaining {
    if (isExpired) return Duration.zero;
    return endDate.difference(DateTime.now());
  }
}

