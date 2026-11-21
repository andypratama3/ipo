import 'dart:math';

int asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }
  return null;
}

double asDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

String asText(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

bool asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return fallback;
}

class Product {
  String id;
  String name;
  String category;
  int price;
  int? stock;
  String description;
  bool available;
  String emoji;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.stock,
    this.description = '',
    this.available = true,
    this.emoji = '🍽️',
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: asText(json['id']),
        name: asText(json['name'], fallback: 'Menu'),
        category: asText(json['category']),
        price: asInt(json['price']),
        stock: asIntOrNull(json['stock']),
        description: asText(json['description']),
        available: json['available'] != false,
        emoji: asText(json['emoji']).isEmpty ? '🍽️' : asText(json['emoji']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'stock': stock,
        'description': description,
        'available': available,
        'emoji': emoji,
      };

  Product copyWith({
    String? id,
    String? name,
    String? category,
    int? price,
    int? Function()? stock,
    String? description,
    bool? available,
    String? emoji,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        price: price ?? this.price,
        stock: stock != null ? stock() : this.stock,
        description: description ?? this.description,
        available: available ?? this.available,
        emoji: emoji ?? this.emoji,
      );
}

class Category {
  String id;
  String label;
  String emoji;

  Category({required this.id, required this.label, required this.emoji});

  factory Category.fromJson(Map<String, dynamic> json) {
    final label = asText(json['label'], fallback: asText(json['id'])).trim();
    return Category(
      id: asText(json['id']),
      label: label.isEmpty ? asText(json['id']) : label,
      emoji: asText(json['emoji']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'emoji': emoji};
}

class CartItem {
  String productId;
  int qty;
  String name;
  int price;
  String emoji;
  String note;

  CartItem({
    required this.productId,
    this.qty = 1,
    required this.name,
    required this.price,
    this.emoji = '',
    this.note = '',
  });

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: asText(json['productId']),
        qty: max(1, asInt(json['qty'], fallback: 1)),
        name: asText(json['name']),
        price: max(0, asInt(json['price'])),
        emoji: asText(json['emoji']),
        note: asText(json['note']),
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'qty': qty,
        'name': name,
        'price': price,
        'emoji': emoji,
        'note': note,
      };
}

class OrderItem {
  String productId;
  String name;
  int price;
  int qty;
  int total;
  String note;

  OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    required this.total,
    this.note = '',
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final qty = max(1, asInt(json['qty'], fallback: 1));
    final price = max(0, asInt(json['price']));
    return OrderItem(
      productId: asText(json['productId']),
      name: asText(json['name'], fallback: 'Menu'),
      price: price,
      qty: qty,
      total: max(0, json['total'] == null ? price * qty : asInt(json['total'])),
      note: asText(json['note']),
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'qty': qty,
        'total': total,
        'note': note,
      };
}

List<OrderItem> parseOrderItems(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((item) => OrderItem.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

class Order {
  String id;
  String clientTxnId;
  String createdAt;
  List<OrderItem> items;
  String orderType;
  String tableNumber;
  int subtotal;
  int discount;
  int total;
  int taxRate;
  bool taxIncluded;
  String payment;
  int paidAmount;
  int changeAmount;
  String status;
  String cashier;
  String note;
  String onlineCode;
  String onlineCustomer;

  Order({
    required this.id,
    this.clientTxnId = '',
    required this.createdAt,
    required this.items,
    this.orderType = 'dine-in',
    this.tableNumber = '',
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.taxRate = 11,
    this.taxIncluded = true,
    this.payment = 'cash',
    this.paidAmount = 0,
    this.changeAmount = 0,
    this.status = 'paid',
    this.cashier = '',
    this.note = '',
    this.onlineCode = '',
    this.onlineCustomer = '',
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final items = parseOrderItems(json['items']);
    final subtotal = json['subtotal'] == null ? asInt(json['total']) : asInt(json['subtotal']);
    return Order(
      id: asText(json['id']),
      clientTxnId: asText(json['clientTxnId']),
      createdAt: asText(json['createdAt'], fallback: DateTime.now().toUtc().toIso8601String()),
      items: items,
      orderType: asText(json['orderType'], fallback: 'dine-in'),
      tableNumber: asText(json['tableNumber']),
      subtotal: subtotal,
      discount: asInt(json['discount']),
      total: asInt(json['total']),
      taxRate: asInt(json['taxRate'], fallback: 11),
      taxIncluded: json['taxIncluded'] != false,
      payment: asText(json['payment'], fallback: 'cash'),
      paidAmount: asInt(json['paidAmount']),
      changeAmount: asInt(json['changeAmount']),
      status: asText(json['status'], fallback: 'paid'),
      cashier: asText(json['cashier']),
      note: asText(json['note']),
      onlineCode: asText(json['onlineCode']),
      onlineCustomer: asText(json['onlineCustomer']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (clientTxnId.isNotEmpty) 'clientTxnId': clientTxnId,
        'createdAt': createdAt,
        'items': items.map((item) => item.toJson()).toList(),
        'orderType': orderType,
        'tableNumber': tableNumber,
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'taxRate': taxRate,
        'taxIncluded': taxIncluded,
        'payment': payment,
        'paidAmount': paidAmount,
        'changeAmount': changeAmount,
        'status': status,
        'cashier': cashier,
        'note': note,
        if (onlineCode.isNotEmpty) 'onlineCode': onlineCode,
        if (onlineCustomer.isNotEmpty) 'onlineCustomer': onlineCustomer,
      };

  int get itemCount => items.fold(0, (sum, item) => sum + item.qty);
}

class PendingOrder {
  String id;
  String createdAt;
  String orderType;
  String tableNumber;
  List<OrderItem> items;
  int subtotal;
  int discount;
  int total;
  String status;
  String? payment;
  String cashier;
  String note;

  PendingOrder({
    required this.id,
    required this.createdAt,
    this.orderType = 'dine-in',
    this.tableNumber = '',
    required this.items,
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.status = 'pending',
    this.payment,
    this.cashier = '',
    this.note = '',
  });

  factory PendingOrder.fromJson(Map<String, dynamic> json) {
    final items = parseOrderItems(json['items']);
    final itemsTotal = items.fold(0, (sum, item) => sum + item.total);
    final discount = asInt(json['discount']).clamp(0, itemsTotal);
    return PendingOrder(
      id: asText(json['id']),
      createdAt: asText(json['createdAt'], fallback: DateTime.now().toUtc().toIso8601String()),
      orderType: asText(json['orderType'], fallback: 'dine-in'),
      tableNumber: asText(json['tableNumber']),
      items: items,
      subtotal: json['subtotal'] == null ? itemsTotal : asInt(json['subtotal']),
      discount: discount,
      total: json['total'] == null ? max(0, itemsTotal - discount) : asInt(json['total']),
      status: json['status'] == 'preparing' ? 'preparing' : 'pending',
      payment: json['payment'] == null ? null : asText(json['payment']),
      cashier: asText(json['cashier']),
      note: asText(json['note']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'orderType': orderType,
        'tableNumber': tableNumber,
        'items': items.map((item) => item.toJson()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'status': status,
        'payment': payment,
        'cashier': cashier,
        'note': note,
      };
}

class OnlineOrderItem {
  String productId;
  int qty;
  int? price;
  String note;

  /// Field lain dari payload platform (mis. nama menu) yang ikut dipertahankan.
  Map<String, dynamic> extra;

  OnlineOrderItem({
    required this.productId,
    required this.qty,
    this.price,
    this.note = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  factory OnlineOrderItem.fromJson(Map<String, dynamic> json) {
    const known = {'productId', 'qty', 'price', 'note'};
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!known.contains(entry.key)) extra[entry.key] = entry.value;
    }
    return OnlineOrderItem(
      productId: asText(json['productId']),
      qty: max(1, asInt(json['qty'], fallback: 1)),
      price: asIntOrNull(json['price']),
      note: asText(json['note']),
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'productId': productId,
        'qty': qty,
        if (price != null) 'price': price,
        if (note.isNotEmpty) 'note': note,
      };
}

class OnlineOrder {
  String id;
  String source;
  String code;
  String customer;
  String note;
  String status;
  String createdAt;
  List<OnlineOrderItem> items;
  String pickupCode;
  int discount;
  int? totalOverride;

  /// Field lain dari payload backend (mis. `partnerOrderId`, `orderType`,
  /// `rejectReason`) yang harus ikut dikirim lagi saat status berubah.
  Map<String, dynamic> extra;

  OnlineOrder({
    required this.id,
    this.source = 'other',
    this.code = '',
    this.customer = '',
    this.note = '',
    this.status = 'baru',
    required this.createdAt,
    required this.items,
    this.pickupCode = '',
    this.discount = 0,
    this.totalOverride,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  factory OnlineOrder.fromJson(Map<String, dynamic> json) {
    const known = {
      'id',
      'source',
      'code',
      'customer',
      'note',
      'status',
      'createdAt',
      'items',
      'pickupCode',
      'discount',
      'total',
    };
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!known.contains(entry.key)) extra[entry.key] = entry.value;
    }
    final rawItems = json['items'];
    return OnlineOrder(
      id: asText(json['id']),
      source: asText(json['source'], fallback: 'other'),
      code: asText(json['code']),
      customer: asText(json['customer']),
      note: asText(json['note']),
      status: asText(json['status'], fallback: 'baru'),
      createdAt: asText(json['createdAt'], fallback: DateTime.now().toUtc().toIso8601String()),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => OnlineOrderItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : [],
      pickupCode: asText(json['pickupCode']),
      discount: asInt(json['discount']),
      totalOverride: asIntOrNull(json['total']),
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'source': source,
        'code': code,
        'customer': customer,
        'note': note,
        'status': status,
        'createdAt': createdAt,
        'items': items.map((item) => item.toJson()).toList(),
        if (pickupCode.isNotEmpty) 'pickupCode': pickupCode,
        'discount': discount,
        if (totalOverride != null) 'total': totalOverride,
      };
}

class AppSettings {
  String businessName;
  String businessAddress;
  String businessPhone;
  int taxRate;
  String qrisStaticPayload;
  String receiptPaperSize;
  String receiptFooter;
  String onlineRejectionMessage;
  String printerModel;
  String printerAddress;
  String printerDeviceName;

  AppSettings({
    this.businessName = 'Mie Pangsit Jakarta',
    this.businessAddress =
        'Jl. Siradj Salman, Air Putih, Kec. Samarinda Ulu, Kota Samarinda, Kalimantan Timur 75124, Indonesia',
    this.businessPhone = '',
    this.taxRate = 11,
    this.qrisStaticPayload = '',
    this.receiptPaperSize = '58mm',
    this.receiptFooter = '',
    this.onlineRejectionMessage = 'Mohon maaf stok habis',
    this.printerModel = 'generic',
    this.printerAddress = '',
    this.printerDeviceName = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        businessName: asText(json['businessName'], fallback: 'Mie Pangsit Jakarta'),
        businessAddress: asText(json['businessAddress'], fallback: defaultBusinessAddress),
        businessPhone: asText(json['businessPhone']),
        taxRate: asInt(json['taxRate'], fallback: 11),
        qrisStaticPayload: asText(json['qrisStaticPayload']),
        receiptPaperSize: asText(json['receiptPaperSize'], fallback: '58mm'),
        receiptFooter: asText(json['receiptFooter']),
        onlineRejectionMessage:
            asText(json['onlineRejectionMessage'], fallback: 'Mohon maaf stok habis'),
        printerModel: asText(json['printerModel'], fallback: 'generic'),
        printerAddress: asText(json['printerAddress']),
        printerDeviceName: asText(json['printerDeviceName']),
      );

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'businessAddress': businessAddress,
        'businessPhone': businessPhone,
        'taxRate': taxRate,
        'qrisStaticPayload': qrisStaticPayload,
        'receiptPaperSize': receiptPaperSize,
        'receiptFooter': receiptFooter,
        'onlineRejectionMessage': onlineRejectionMessage,
        'printerModel': printerModel,
        'printerAddress': printerAddress,
        'printerDeviceName': printerDeviceName,
      };

  AppSettings copyWith({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    int? taxRate,
    String? qrisStaticPayload,
    String? receiptPaperSize,
    String? receiptFooter,
    String? onlineRejectionMessage,
    String? printerModel,
    String? printerAddress,
    String? printerDeviceName,
  }) =>
      AppSettings(
        businessName: businessName ?? this.businessName,
        businessAddress: businessAddress ?? this.businessAddress,
        businessPhone: businessPhone ?? this.businessPhone,
        taxRate: taxRate ?? this.taxRate,
        qrisStaticPayload: qrisStaticPayload ?? this.qrisStaticPayload,
        receiptPaperSize: receiptPaperSize ?? this.receiptPaperSize,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        onlineRejectionMessage: onlineRejectionMessage ?? this.onlineRejectionMessage,
        printerModel: printerModel ?? this.printerModel,
        printerAddress: printerAddress ?? this.printerAddress,
        printerDeviceName: printerDeviceName ?? this.printerDeviceName,
      );

  static const defaultBusinessAddress =
      'Jl. Siradj Salman, Air Putih, Kec. Samarinda Ulu, Kota Samarinda, Kalimantan Timur 75124, Indonesia';
}

class LocalUser {
  String username;
  String name;
  String role;
  bool active;
  String password;

  LocalUser({
    required this.username,
    required this.name,
    this.role = 'Kasir',
    this.active = true,
    required this.password,
  });

  bool get isOwner => role == 'Pemilik';

  factory LocalUser.fromJson(Map<String, dynamic> json) => LocalUser(
        username: asText(json['username']).trim().toLowerCase(),
        name: asText(json['name'], fallback: asText(json['username'])).trim(),
        role: json['role'] == 'Pemilik' ? 'Pemilik' : 'Kasir',
        active: json['active'] != false,
        password: asText(json['password']),
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'name': name,
        'role': role,
        'active': active,
        'password': password,
      };
}

/// Akun yang tersimpan di server IPOS (`GET /api/users`).
class ServerUser {
  final String id;
  String username;
  String name;
  String role;
  bool active;

  ServerUser({
    required this.id,
    required this.username,
    required this.name,
    this.role = 'Kasir',
    this.active = true,
  });

  bool get isOwner => role == 'Pemilik';

  factory ServerUser.fromJson(Map<String, dynamic> json) {
    final username = asText(json['username']).trim().toLowerCase();
    return ServerUser(
      id: asText(json['id']),
      username: username,
      name: asText(
        json['displayName'],
        fallback: asText(json['name'], fallback: username),
      ).trim(),
      role: json['role'] == 'Pemilik' ? 'Pemilik' : 'Kasir',
      active: json['active'] != false,
    );
  }
}

class SessionUser {
  String username;
  String name;
  String role;
  int loginAt;
  String loginDay;
  int loginMinute;

  SessionUser({
    required this.username,
    required this.name,
    required this.role,
    required this.loginAt,
    required this.loginDay,
    required this.loginMinute,
  });

  bool get isOwner => role == 'Pemilik';

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        username: asText(json['username']),
        name: asText(json['name'], fallback: asText(json['username'])),
        role: json['role'] == 'Pemilik' ? 'Pemilik' : 'Kasir',
        loginAt: asInt(json['loginAt'], fallback: DateTime.now().millisecondsSinceEpoch),
        loginDay: asText(json['loginDay']),
        loginMinute: asInt(json['loginMinute']),
      );

  Map<String, dynamic> toJson() => {
        'username': username,
        'name': name,
        'role': role,
        'loginAt': loginAt,
        'loginDay': loginDay,
        'loginMinute': loginMinute,
      };
}

class Snapshot {
  String id;
  String at;
  String reason;
  int ordersCount;
  Map<String, dynamic> data;

  Snapshot({
    required this.id,
    required this.at,
    required this.reason,
    required this.ordersCount,
    required this.data,
  });

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
        id: asText(json['id']),
        at: asText(json['at']),
        reason: asText(json['reason']),
        ordersCount: asInt(json['orders']),
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data']) : <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at,
        'reason': reason,
        'orders': ordersCount,
        'data': data,
      };
}

class SyncRow {
  final String table;
  final String id;
  final Map<String, dynamic> payload;
  final bool deleted;
  final String? updatedAt;
  final String? deviceId;

  SyncRow({
    required this.table,
    required this.id,
    required this.payload,
    this.deleted = false,
    this.updatedAt,
    this.deviceId,
  });

  factory SyncRow.fromJson(String table, Map<String, dynamic> json) => SyncRow(
        table: table,
        id: asText(json['id']),
        payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload']) : <String, dynamic>{},
        deleted: json['deleted'] == true,
        updatedAt: asText(json['updatedAt']).isEmpty ? asText(json['updated_at']) : asText(json['updatedAt']),
        deviceId: asText(json['device_id']).isEmpty ? null : asText(json['device_id']),
      );
}

class OutboxEntry {
  final String table;
  final String id;
  final Map<String, dynamic> payload;
  final bool deleted;
  final String deviceId;
  int attempts;
  String lastError;

  OutboxEntry({
    required this.table,
    required this.id,
    required this.payload,
    required this.deleted,
    required this.deviceId,
    this.attempts = 0,
    this.lastError = '',
  });
}

class CartTotals {
  final int subtotal;
  final int discount;
  final int total;

  const CartTotals({required this.subtotal, required this.discount, required this.total});
}
