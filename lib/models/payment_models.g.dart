// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentTransaction _$PaymentTransactionFromJson(Map<String, dynamic> json) =>
    PaymentTransaction(
      id: json['id'] as String,
      productId: json['productId'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      status: $enumDecode(_$PaymentStatusEnumMap, json['status']),
      gateway: $enumDecode(_$PaymentGatewayEnumMap, json['gateway']),
      gatewayTransactionId: json['gatewayTransactionId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      userId: json['userId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isTest: json['isTest'] as bool? ?? false,
    );

Map<String, dynamic> _$PaymentTransactionToJson(PaymentTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'productId': instance.productId,
      'amount': instance.amount,
      'currency': instance.currency,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'gateway': _$PaymentGatewayEnumMap[instance.gateway]!,
      'gatewayTransactionId': instance.gatewayTransactionId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'userId': instance.userId,
      'metadata': instance.metadata,
      'isTest': instance.isTest,
    };

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.completed: 'completed',
  PaymentStatus.failed: 'failed',
  PaymentStatus.cancelled: 'cancelled',
  PaymentStatus.refunded: 'refunded',
};

const _$PaymentGatewayEnumMap = {
  PaymentGateway.stripe: 'stripe',
  PaymentGateway.paypal: 'paypal',
  PaymentGateway.iap: 'iap',
};

PaymentResult _$PaymentResultFromJson(Map<String, dynamic> json) =>
    PaymentResult(
      success: json['success'] as bool,
      transactionId: json['transactionId'] as String?,
      gatewayTransactionId: json['gatewayTransactionId'] as String?,
      message: json['message'] as String?,
      error: json['error'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$PaymentResultToJson(PaymentResult instance) =>
    <String, dynamic>{
      'success': instance.success,
      'transactionId': instance.transactionId,
      'gatewayTransactionId': instance.gatewayTransactionId,
      'message': instance.message,
      'error': instance.error,
      'data': instance.data,
    };

PaymentReceipt _$PaymentReceiptFromJson(Map<String, dynamic> json) =>
    PaymentReceipt(
      id: json['id'] as String,
      transactionId: json['transactionId'] as String,
      receiptNumber: json['receiptNumber'] as String,
      productName: json['productName'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      status: $enumDecode(_$PaymentStatusEnumMap, json['status']),
      gateway: $enumDecode(_$PaymentGatewayEnumMap, json['gateway']),
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      downloadUrl: json['downloadUrl'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      customer:
          ReceiptCustomer.fromJson(json['customer'] as Map<String, dynamic>),
      vendor: ReceiptVendor.fromJson(json['vendor'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PaymentReceiptToJson(PaymentReceipt instance) =>
    <String, dynamic>{
      'id': instance.id,
      'transactionId': instance.transactionId,
      'receiptNumber': instance.receiptNumber,
      'productName': instance.productName,
      'amount': instance.amount,
      'currency': instance.currency,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'gateway': _$PaymentGatewayEnumMap[instance.gateway]!,
      'issuedAt': instance.issuedAt.toIso8601String(),
      'downloadUrl': instance.downloadUrl,
      'details': instance.details,
      'customer': instance.customer,
      'vendor': instance.vendor,
    };

ReceiptCustomer _$ReceiptCustomerFromJson(Map<String, dynamic> json) =>
    ReceiptCustomer(
      name: json['name'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      postalCode: json['postalCode'] as String?,
    );

Map<String, dynamic> _$ReceiptCustomerToJson(ReceiptCustomer instance) =>
    <String, dynamic>{
      'name': instance.name,
      'email': instance.email,
      'address': instance.address,
      'city': instance.city,
      'country': instance.country,
      'postalCode': instance.postalCode,
    };

ReceiptVendor _$ReceiptVendorFromJson(Map<String, dynamic> json) =>
    ReceiptVendor(
      name: json['name'] as String,
      address: json['address'] as String,
      city: json['city'] as String,
      country: json['country'] as String,
      postalCode: json['postalCode'] as String,
      taxId: json['taxId'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
    );

Map<String, dynamic> _$ReceiptVendorToJson(ReceiptVendor instance) =>
    <String, dynamic>{
      'name': instance.name,
      'address': instance.address,
      'city': instance.city,
      'country': instance.country,
      'postalCode': instance.postalCode,
      'taxId': instance.taxId,
      'email': instance.email,
      'phone': instance.phone,
    };

SubscriptionPlan _$SubscriptionPlanFromJson(Map<String, dynamic> json) =>
    SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      duration: json['duration'] as String,
      features:
          (json['features'] as List<dynamic>).map((e) => e as String).toList(),
      isPopular: json['isPopular'] as bool? ?? false,
      originalPrice: json['originalPrice'] as String?,
      discountPercentage: (json['discountPercentage'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SubscriptionPlanToJson(SubscriptionPlan instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'price': instance.price,
      'currency': instance.currency,
      'duration': instance.duration,
      'features': instance.features,
      'isPopular': instance.isPopular,
      'originalPrice': instance.originalPrice,
      'discountPercentage': instance.discountPercentage,
    };

UserSubscription _$UserSubscriptionFromJson(Map<String, dynamic> json) =>
    UserSubscription(
      id: json['id'] as String,
      userId: json['userId'] as String,
      planId: json['planId'] as String,
      status: $enumDecode(_$PaymentStatusEnumMap, json['status']),
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      autoRenew: json['autoRenew'] as bool,
      gateway: $enumDecode(_$PaymentGatewayEnumMap, json['gateway']),
      gatewaySubscriptionId: json['gatewaySubscriptionId'] as String?,
      nextBillingDate: json['nextBillingDate'] == null
          ? null
          : DateTime.parse(json['nextBillingDate'] as String),
      plan: json['plan'] == null
          ? null
          : SubscriptionPlan.fromJson(json['plan'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$UserSubscriptionToJson(UserSubscription instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'planId': instance.planId,
      'status': _$PaymentStatusEnumMap[instance.status]!,
      'startDate': instance.startDate.toIso8601String(),
      'endDate': instance.endDate.toIso8601String(),
      'autoRenew': instance.autoRenew,
      'gateway': _$PaymentGatewayEnumMap[instance.gateway]!,
      'gatewaySubscriptionId': instance.gatewaySubscriptionId,
      'nextBillingDate': instance.nextBillingDate?.toIso8601String(),
      'plan': instance.plan,
    };
