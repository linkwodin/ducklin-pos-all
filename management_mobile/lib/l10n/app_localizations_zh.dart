// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'POS 管理系統';

  @override
  String get loginSubtitle => '請使用管理帐戶登入';

  @override
  String get signIn => '登入';

  @override
  String get username => '使用者名稱';

  @override
  String get usernameRequired => '請輸入使用者名稱';

  @override
  String get password => '密碼';

  @override
  String get passwordRequired => '請輸入密碼';

  @override
  String useBiometricNextTime(String label) {
    return '下次使用$label';
  }

  @override
  String get biometricUnlockHint => '無需輸入密碼即可解鎖应用程序';

  @override
  String unlockWithBiometric(String label) {
    return '使用$label解鎖';
  }

  @override
  String get unlock => '解鎖';

  @override
  String get checking => '证证中…';

  @override
  String get usePasswordInstead => '改用密碼登入';

  @override
  String biometricFailed(String label) {
    return '$label证证失敗';
  }

  @override
  String get logout => '登出';

  @override
  String get logoutConfirm => '確定登出？';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get retry => '重試';

  @override
  String get save => '储存';

  @override
  String get add => '新增';

  @override
  String get create => '建立';

  @override
  String get none => '無';

  @override
  String get all => '全部';

  @override
  String get status => '狀態';

  @override
  String get store => '门店';

  @override
  String get client => '客戶';

  @override
  String get created => '建立時間';

  @override
  String get courier => '快递';

  @override
  String get tracking => '追蹤号碼';

  @override
  String get items => '品项';

  @override
  String get documents => '文件';

  @override
  String get overview => '概览';

  @override
  String get shipments => '出货';

  @override
  String get process => '流程';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChineseTraditional => '繁體中文';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get menuDashboard => '仪表板';

  @override
  String get menuReports => '報表';

  @override
  String get menuProductsGroup => '产品';

  @override
  String get menuProducts => '产品';

  @override
  String get menuCategories => '分类';

  @override
  String get menuSectors => '部门';

  @override
  String get menuInventoryGroup => '库存';

  @override
  String get menuStock => '库存';

  @override
  String get menuRestock => '补货订单';

  @override
  String get menuPosOrders => 'POS 订单';

  @override
  String get menuWholesaleGroup => '批发';

  @override
  String get menuWholesaleOrders => '订单';

  @override
  String get menuShipments => '出货';

  @override
  String get menuWholesaleClients => '客戶';

  @override
  String get menuSettingsGroup => '设定';

  @override
  String get menuUsers => '使用者';

  @override
  String get menuStores => '商店';

  @override
  String get menuDevices => '设备';

  @override
  String get menuCurrency => '汇率';

  @override
  String get menuCompany => '公司设定';

  @override
  String get management => '管理';

  @override
  String get roleManagement => '管理';

  @override
  String get roleHQStaff => '总部员工';

  @override
  String get roleSupervisor => '主管';

  @override
  String get roleCashier => '收銀员';

  @override
  String get roleStaff => '员工';

  @override
  String get searchOrderPoClient => '搜寻订单、采購单、客戶…';

  @override
  String get tabDashboard => '仪表板';

  @override
  String get tabList => '列表';

  @override
  String get nothingHere => '暂無资料';

  @override
  String get shipmentUpdated => '出货已更新';

  @override
  String get shipmentTitle => '出货';

  @override
  String shipmentNumber(int id) {
    return '出货 #$id';
  }

  @override
  String boxesCount(int count) {
    return '$count 箱';
  }

  @override
  String get monitorPacking => '装箱中';

  @override
  String get monitorPackedAwaitingCourier => '已装箱 — 待快递取件';

  @override
  String get monitorShipped => '已出货';

  @override
  String get monitorCompletedRecent => '已完成（近期）';

  @override
  String get batchPack => '批次装箱';

  @override
  String get courierPickup => '快递取件';

  @override
  String get workflowPickPack => '拣货与装箱';

  @override
  String get workflowPickPackSub => '扫描品项並确认箱数';

  @override
  String get workflowCourier => '快递资讯';

  @override
  String get workflowCourierSub => '快递公司、追蹤号碼与送达日期';

  @override
  String get workflowHandoff => '交付签收';

  @override
  String get workflowHandoffUploaded => '已上传签收单';

  @override
  String get workflowHandoffUploadShipped => '上传签收单';

  @override
  String get workflowHandoffUploadAndShip => '上传签收单並标记已出货';

  @override
  String get saveDetails => '储存资讯';

  @override
  String get batchPacking => '批次装箱';

  @override
  String get packingQueueComplete => '装箱佇列已完成';

  @override
  String get noShipmentsInQueue => '佇列中沒有出货单';

  @override
  String get skipThisShipment => '跳過此出货单';

  @override
  String get startPacking => '开始装箱';

  @override
  String get shipmentStatusAssigned => '已分配';

  @override
  String get shipmentStatusPacking => '装箱中';

  @override
  String get shipmentStatusPacked => '已装箱';

  @override
  String get shipmentStatusShipped => '已出货';

  @override
  String get shipmentStatusCompleted => '已完成';

  @override
  String get filterPendingApproval => '待审批';

  @override
  String get filterAssignShipment => '分配出货';

  @override
  String get filterAwaitingPayment => '待付款';

  @override
  String get filterCompleted => '已完成';

  @override
  String get filterRejected => '已拒绝';

  @override
  String get filterDeleted => '已删除';

  @override
  String get wholesaleStatusRejected => '已拒绝';

  @override
  String get wholesaleStatusDeleted => '已删除';

  @override
  String get wholesaleStatusCompleted => '已完成';

  @override
  String get wholesaleStatusPendingOrderConfirmation => '待订单确认';

  @override
  String get wholesaleStatusPendingPacking => '待装箱';

  @override
  String get wholesaleStatusInTransit => '运送中';

  @override
  String get wholesaleStatusPendingInvoice => '待发送发票';

  @override
  String get wholesaleStatusPendingPayment => '待收款确认';

  @override
  String get wholesaleStatusPendingApproval => '待审批';

  @override
  String get wholesaleStatusAssignShipment => '分配出货';

  @override
  String get wholesaleStatusApproved => '已核准';

  @override
  String get posFilterPending => '待處理';

  @override
  String get posFilterPaid => '已付款';

  @override
  String get posFilterPickedUp => '已取货';

  @override
  String get posFilterCancelled => '已取消';

  @override
  String get takePhoto => '拍照';

  @override
  String get chooseFromGallery => '从相簿选擇';

  @override
  String get chooseFile => '选擇档案';

  @override
  String get rejectOrder => '拒绝订单';

  @override
  String get rejectReason => '原因';

  @override
  String get reject => '拒绝';

  @override
  String get noDocumentsYet => '尚無文件';

  @override
  String get uploadPoAttachment => '上传采購单附件';

  @override
  String get assigned => '已分配';

  @override
  String get move => '移动';

  @override
  String get remove => '移除';

  @override
  String get skip => '跳過';

  @override
  String get emailSkipped => '已跳過邮件';

  @override
  String get emailSent => '邮件已发送';

  @override
  String get resubmit => '重新提交';

  @override
  String get selectStore => '选擇门店';

  @override
  String get assignByDefaults => '依预设分配';

  @override
  String get changeAssignment => '变更分配';

  @override
  String get regenerateOrderConfirmationPdf => '重新产生订单确认 PDF';

  @override
  String linesCount(int count) {
    return '$count 行';
  }

  @override
  String get generateInvoice => '产生发票';

  @override
  String orderTotal(String amount) {
    return '订单总额：$amount';
  }

  @override
  String proofTotal(String amount) {
    return '凭证总额：$amount';
  }

  @override
  String get uploadPaymentProof => '上传付款凭证';

  @override
  String get confirmPaymentReceived => '确认已收款';

  @override
  String get paymentConfirmed => '收款已确认';

  @override
  String get moveReassign => '移动 / 重新分配';

  @override
  String moveFrom(String store) {
    return '从 $store';
  }

  @override
  String get skipEmail => '跳過邮件';

  @override
  String get loadReport => '载入報表';

  @override
  String get posRevenue => 'POS 营收';

  @override
  String posOrdersCount(int count) {
    return 'POS 订单：$count';
  }

  @override
  String get allStores => '全部门店';

  @override
  String get settingsSaved => '设定已储存';

  @override
  String get saveSettings => '储存设定';

  @override
  String get createWholesaleOrder => '建立批发订单';

  @override
  String get addAtLeastOneProduct => '請至少新增一项产品';

  @override
  String get companyAddress => '公司地址';

  @override
  String get sourceClientPo => '客戶采購单';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceEmail => '电邮';

  @override
  String get sourceNa => '不適用';

  @override
  String get lineItems => '订单行';

  @override
  String unitPrice(String amount) {
    return '单價：$amount';
  }

  @override
  String poAttachments(int count) {
    return '采購单附件（$count）';
  }

  @override
  String get createOrder => '建立订单';

  @override
  String get deliveryLocations => '送货地点';

  @override
  String get auditLog => '审計日誌';

  @override
  String get registerDevice => '注册设备';

  @override
  String get register => '注册';

  @override
  String get newCategory => '新分类';

  @override
  String get newSector => '新部门';

  @override
  String get newStore => '新商店';

  @override
  String get warehouse => '仓库';

  @override
  String get receive => '收货';

  @override
  String get markPaid => '标记已付款';

  @override
  String get markComplete => '标记完成';

  @override
  String get cancelOrder => '取消订单？';

  @override
  String get cancelOrderAction => '取消订单';

  @override
  String get courierDetails => '快递资讯';

  @override
  String get courierDetailsHint => '輸入快递与追蹤资讯。輸入時會顯示建議选项。';

  @override
  String get courierHint => '輸入或从建議中选擇';

  @override
  String get trackingNumber => '追蹤号碼';

  @override
  String get deliveryProofLocked => '已上传交付证明 — 快递资讯已鎖定。';

  @override
  String shipmentProgress(int current, int total) {
    return '出货 $current / $total';
  }

  @override
  String get markShipped => '标记已出货';

  @override
  String get deliveryHandoffHint => '快递取件時，請上传签收单並标记為已出货。';

  @override
  String get name => '名稱';

  @override
  String get back => '返回';

  @override
  String get no => '否';

  @override
  String get product => '产品';

  @override
  String get quantity => '數量';

  @override
  String get notes => '备注';

  @override
  String get phone => '电话';

  @override
  String get contact => '联络人';

  @override
  String get sector => '部门';

  @override
  String qtyTimes(String qty, String price) {
    return '數量 $qty × $price';
  }

  @override
  String get packShipment => '装箱出货';

  @override
  String packOrder(String order) {
    return '装箱 $order';
  }

  @override
  String get manualBarcode => '手動條碼';

  @override
  String get nextConfirmBoxes => '下一步 — 确认箱数';

  @override
  String get confirmBoxes => '确认箱数';

  @override
  String get finishPacking => '完成装箱';

  @override
  String get products => '产品';

  @override
  String get boxes => '箱数';

  @override
  String expectedBoxes(String qty, int count) {
    return '數量 $qty · 预期箱数 $count';
  }

  @override
  String get deliveryLocation => '送货地点';

  @override
  String get orderChannel => '订单来源';

  @override
  String get poNumber => '采購单号';

  @override
  String get poDate => '采購单日期 (YYYY-MM-DD)';

  @override
  String get paymentTerms => '付款條件';

  @override
  String get shippingFee => '运費';

  @override
  String get paymentProofDetails => '付款凭证详情';

  @override
  String get amount => '金额';

  @override
  String get transferDate => '转帐日期';

  @override
  String get transferredToAccount => '转入帐戶';

  @override
  String get saveAndUploadProof => '储存並上传凭证';

  @override
  String get orderConfirmation => '订单确认';

  @override
  String get rejectedSection => '已拒绝';

  @override
  String get deliveryCompleteEmail => '送达完成邮件';

  @override
  String get invoice => '发票';

  @override
  String get assignLinesHint => '將所有订单行分配至门店，然後确认分配以核准此订单。';

  @override
  String get assignLinesHintStaged => '將订单行分配至门店。綠色门店标籤可完全滿足待分配數量；橙色可滿足部分。';

  @override
  String get stageForStore => '暂存至门店';

  @override
  String get assignPendingQty => '分配待處理數量';

  @override
  String get sendDeliveryCompleteEmail => '发送送达完成邮件';

  @override
  String get resendDeliveryCompleteEmail => '重新发送送达完成邮件';

  @override
  String get sendInvoiceEmail => '发送发票邮件';

  @override
  String get resendInvoiceEmail => '重新发送发票邮件';

  @override
  String get skipReasonRequired => '跳過此邮件必須填寫原因';

  @override
  String get shipmentsAfterAssignment => '门店分配後，出货单將顯示於此。';

  @override
  String get todayPosRevenue => '今日 POS 营收';

  @override
  String get lowStockItems => '低库存品项';

  @override
  String get pendingRestocks => '待處理补货';

  @override
  String get pendingWholesaleOrders => '待處理批发订单';

  @override
  String get companyName => '公司名稱';

  @override
  String get address => '地址';

  @override
  String get city => '城市';

  @override
  String get postcode => '邮递区号';

  @override
  String get telephone => '电话';

  @override
  String get email => '电邮';

  @override
  String get paymentInfo => '付款资讯';

  @override
  String get shipmentCouriersField => '出货快递公司';

  @override
  String get deviceCode => '设备代碼';

  @override
  String get deviceName => '设备名稱';

  @override
  String get currencyCode => '货币代碼';

  @override
  String get rateToGbp => '兌 GBP 汇率';

  @override
  String get addCurrencyRate => '新增汇率';

  @override
  String rateLabel(String rate) {
    return '汇率：$rate';
  }

  @override
  String get adjustStock => '调整库存';

  @override
  String adjustStockTitle(String name) {
    return '调整 $name';
  }

  @override
  String get reason => '原因';

  @override
  String get searchProducts => '搜寻产品';

  @override
  String get firstName => '名字';

  @override
  String get lastName => '姓氏';

  @override
  String get newPasswordOptional => '新密碼（选填）';

  @override
  String get rolePosUser => 'POS 使用者';

  @override
  String locationsCount(int count) {
    return '$count 个地点';
  }

  @override
  String storeNumber(int id) {
    return '门店 #$id';
  }

  @override
  String restockNumber(int id) {
    return '补货 #$id';
  }

  @override
  String get selectCourier => '請选擇快递公司';

  @override
  String get selectAtLeastOneShipment => '請至少选擇一筆出货单';

  @override
  String get noCouriersConfigured => '公司设定中未设定快递公司。';

  @override
  String get selectOrders => '选擇订单';

  @override
  String get scanDeliveryNote => '扫描签收单';

  @override
  String get confirmStep => '确认';

  @override
  String noMatchingShipment(String code) {
    return '找不到符合的出货单：$code';
  }

  @override
  String markedShippedVia(int count, String courier) {
    return '已將 $count 筆出货标记為已出货（$courier）';
  }

  @override
  String courierLabel(String name) {
    return '快递：$name';
  }

  @override
  String shipmentsCountLabel(int count) {
    return '出货单：$count';
  }

  @override
  String get more => '更多';

  @override
  String get apiServer => 'API 服务器';

  @override
  String get environment => '環境';

  @override
  String get biometricUnlock => '生物辨識解鎖';

  @override
  String get biometricUnlockSubtitle => '开启应用程序時需要 Face ID / 指纹';

  @override
  String get startDate => '开始日期 (YYYY-MM-DD)';

  @override
  String get endDate => '結束日期 (YYYY-MM-DD)';

  @override
  String get toStore => '目标门店';

  @override
  String get stepCreated => '已建立';

  @override
  String get stepOrderConfirmation => '订单确认';

  @override
  String get stepStartShipment => '开始出货';

  @override
  String get stepFinishShipment => '完成出货';

  @override
  String get stepInvoiceEmail => '发票邮件';

  @override
  String get stepPaymentConfirmation => '收款确认';

  @override
  String get stepComplete => '完成';

  @override
  String get total => '总計';

  @override
  String get ref => '参考号';

  @override
  String get channel => '来源';

  @override
  String get rejection => '拒绝原因';

  @override
  String get unassigned => '未分配';

  @override
  String qtyAssigned(String qty, String assigned) {
    return '數量 $qty · 已分配 $assigned';
  }

  @override
  String get staged => '暂存';

  @override
  String get newUser => '新增使用者';

  @override
  String get editUser => '编辑使用者';

  @override
  String get staff => '员工';

  @override
  String get subtotal => '小计';

  @override
  String get discount => '折扣';

  @override
  String get posOrder => 'POS 订单';

  @override
  String get confirmAllocationApprove => '确认分配並核准';

  @override
  String get confirmAllocation => '确认分配';

  @override
  String get allLinesAssigned => '所有订单行已分配至门店。';

  @override
  String get changeAssignmentWhilePacking => '出货单仍在分配/装箱阶段時，可变更分配。';

  @override
  String get orderConfirmationEmail => '订单确认邮件';

  @override
  String get sendOrderConfirmationEmail => '发送订单确认邮件';

  @override
  String get resendOrderConfirmationEmail => '重新发送订单确认邮件';

  @override
  String get paymentConfirmationSection => '收款确认';

  @override
  String get actionNeeded => '需要操作';

  @override
  String get forceComplete => '强制完成';

  @override
  String get next => '下一步';

  @override
  String get confirmPickup => '确认取件';

  @override
  String get scanHint => '订单号、采購单、参考号…';

  @override
  String selectedOrder(String order) {
    return '已选擇 $order';
  }

  @override
  String totalBoxes(int count) {
    return '总箱数：$count';
  }

  @override
  String get saveChanges => '储存变更';

  @override
  String get createUser => '建立使用者';

  @override
  String get required => '必填';

  @override
  String get send => '发送';

  @override
  String get toField => '收件人';

  @override
  String get ccField => '副本';

  @override
  String get bccField => '密件副本';

  @override
  String get subjectField => '主旨';

  @override
  String get messageField => '内容';

  @override
  String get attachments => '附件';

  @override
  String get focusMode => '专注';

  @override
  String get focusModeTooltip => '专注模式 — 扫描時屏幕保持开启';

  @override
  String get scanStep => '1/2 扫描';

  @override
  String get boxesStep => '2/2 箱数';

  @override
  String needQtyBoxes(String qty, String boxes) {
    return '需要 $qty · 箱数 $boxes';
  }

  @override
  String get turnPhoneNext => '转動或移动手機至下一个产品';

  @override
  String get phoneTurnedNext => '手機已转向下一个产品';

  @override
  String get pauseComplete => '暂停完成';

  @override
  String pauseForSeconds(int seconds) {
    return '移动時暂停 $seconds 秒';
  }

  @override
  String reasonPrefix(String reason) {
    return '原因：$reason';
  }

  @override
  String skippedAt(String date) {
    return '跳過於 $date';
  }

  @override
  String skippedBy(String name) {
    return '跳過者 $name';
  }

  @override
  String previouslySentAt(String date) {
    return '先前发送於 $date';
  }

  @override
  String get noPaymentProof => '無付款凭证';

  @override
  String get forceConfirmPayment => '强制确认收款';

  @override
  String get noPaymentProofWarning => '尚未上传付款凭证。確定要在沒有凭证的情況下确认嗎？';

  @override
  String get forceConfirmWarning => '這將在未符合凭证总额的情況下标记為已收款。僅在確定款项已收齊時使用。';

  @override
  String get confirmPaymentQuestion => '确认此订单已收到款项？';

  @override
  String get proofShortfallHint => '凭证总额低於订单总额。收款确认後將無法再上传凭证。';

  @override
  String get snackSelectStore => '請选擇门店';

  @override
  String get snackShipmentPacked => '該门店出货单已装箱或已出货';

  @override
  String get snackLineStaged => '订单行已暂存待分配';

  @override
  String get snackDefaultStaged => '预设分配已暂存 — 准备好後請确认';

  @override
  String get snackAssignAllLines => '确认前請分配所有订单行';

  @override
  String get snackOrderApproved => '订单已核准並分配';

  @override
  String get snackAllocationConfirmedContinue => '分配已确认 — 請发送订单确认邮件或跳過以繼續';

  @override
  String get snackAssignmentRemoved => '分配已移除';

  @override
  String get snackAssignmentMoved => '分配已移动';

  @override
  String get snackPaymentProofUploaded => '付款凭证已上传';

  @override
  String get snackPaymentProofAutoConfirmed => '付款凭证已上传，收款已自动确认。';

  @override
  String get lineAssigned => '订单行已分配';

  @override
  String get assignedByDefaults => '已依预设分配';

  @override
  String get orderResubmitted => '订单已重新提交';

  @override
  String get orderConfirmationRegenerated => '订单确认已重新产生';

  @override
  String get invoiceGenerated => '发票已产生';

  @override
  String qtyLabel(String qty) {
    return '數量 $qty';
  }

  @override
  String filesSelected(int count) {
    return '已选擇 $count 个档案';
  }

  @override
  String get enterValidAmount => '請輸入有效金额';

  @override
  String get selectTransferDate => '請选擇转帐日期';

  @override
  String get selectDestinationAccount => '請选擇目标帐戶';

  @override
  String get role => '角色';

  @override
  String get newClient => '新增客戶';

  @override
  String get editClient => '编辑客戶';

  @override
  String get findNextItemToScan => '寻找下一个要扫描的品项';

  @override
  String get active => '启用';

  @override
  String get inactive => '停用';

  @override
  String get po => '采购单';

  @override
  String get resend => '重新发送';

  @override
  String get resendEmail => '重新发送邮件';

  @override
  String get sendOrderConfirmationEmailDescription => '向客户发送附带附件的订单确认邮件。';

  @override
  String get sendDeliveryCompleteEmailDescription => '发送附带已签收送货单的送货完成邮件。';

  @override
  String get sendInvoiceEmailDescription => '发送附带发票及可选送货文件的发票邮件。';

  @override
  String get emailRecipientsRequired => '至少需要一个收件人电邮';

  @override
  String invalidEmailAddress(String email) {
    return '无效电邮：$email';
  }

  @override
  String get selectAtLeastOneAttachment => '请至少选择一个附件';

  @override
  String get sendSkippedEmailNow => '此邮件先前已跳过，您现在仍可发送。';

  @override
  String attachmentsList(String list) {
    return '附件：$list';
  }

  @override
  String filesList(String list) {
    return '文件：$list';
  }

  @override
  String get invoiceDeliveryDocsOptional => '发票邮件中的送货单与送货证明为可选。';

  @override
  String get emailRecipientsHint => 'email@example.com, another@example.com';

  @override
  String paymentProofNumber(int id) {
    return '付款凭证 #$id';
  }

  @override
  String get productNotFound => '找不到产品';

  @override
  String productNotFoundDetail(String code) {
    return '条码「$code」与此出货单上的任何品项不符。';
  }

  @override
  String get quantityAlreadyComplete => '数量已完成';

  @override
  String quantityAlreadyCompleteDetail(
    String product,
    String scanned,
    String expected,
  ) {
    return '$product 已扫描完成（$scanned/$expected）。请扫描其他品项。';
  }

  @override
  String scanProgress(String product, String scanned, String expected) {
    return '$product：$scanned / $expected';
  }

  @override
  String get biometricEnableReason => '启用 POS 管理系统的生物识别解锁';

  @override
  String get biometricUnlockReason => '解锁 POS 管理系统';

  @override
  String get restockStatusInitiated => '已发起';

  @override
  String get restockStatusInTransit => '运送中';

  @override
  String get restockStatusReceived => '已收到';

  @override
  String get markedShippedSnack => '已标记出货';

  @override
  String get shipmentMarkedAwaitProof => '出货单已标记出货。收到已签收送货单后请上传。';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'POS 管理系統';

  @override
  String get loginSubtitle => '請使用管理帳戶登入';

  @override
  String get signIn => '登入';

  @override
  String get username => '使用者名稱';

  @override
  String get usernameRequired => '請輸入使用者名稱';

  @override
  String get password => '密碼';

  @override
  String get passwordRequired => '請輸入密碼';

  @override
  String useBiometricNextTime(String label) {
    return '下次使用$label';
  }

  @override
  String get biometricUnlockHint => '無需輸入密碼即可解鎖應用程式';

  @override
  String unlockWithBiometric(String label) {
    return '使用$label解鎖';
  }

  @override
  String get unlock => '解鎖';

  @override
  String get checking => '驗證中…';

  @override
  String get usePasswordInstead => '改用密碼登入';

  @override
  String biometricFailed(String label) {
    return '$label驗證失敗';
  }

  @override
  String get logout => '登出';

  @override
  String get logoutConfirm => '確定登出？';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確認';

  @override
  String get retry => '重試';

  @override
  String get save => '儲存';

  @override
  String get add => '新增';

  @override
  String get create => '建立';

  @override
  String get none => '無';

  @override
  String get all => '全部';

  @override
  String get status => '狀態';

  @override
  String get store => '門店';

  @override
  String get client => '客戶';

  @override
  String get created => '建立時間';

  @override
  String get courier => '快遞';

  @override
  String get tracking => '追蹤號碼';

  @override
  String get items => '品項';

  @override
  String get documents => '文件';

  @override
  String get overview => '概覽';

  @override
  String get shipments => '出貨';

  @override
  String get process => '流程';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChineseTraditional => '繁體中文';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get menuDashboard => '儀表板';

  @override
  String get menuReports => '報表';

  @override
  String get menuProductsGroup => '產品';

  @override
  String get menuProducts => '產品';

  @override
  String get menuCategories => '分類';

  @override
  String get menuSectors => '部門';

  @override
  String get menuInventoryGroup => '庫存';

  @override
  String get menuStock => '庫存';

  @override
  String get menuRestock => '補貨訂單';

  @override
  String get menuPosOrders => 'POS 訂單';

  @override
  String get menuWholesaleGroup => '批發';

  @override
  String get menuWholesaleOrders => '訂單';

  @override
  String get menuShipments => '出貨';

  @override
  String get menuWholesaleClients => '客戶';

  @override
  String get menuSettingsGroup => '設定';

  @override
  String get menuUsers => '使用者';

  @override
  String get menuStores => '商店';

  @override
  String get menuDevices => '設備';

  @override
  String get menuCurrency => '匯率';

  @override
  String get menuCompany => '公司設定';

  @override
  String get management => '管理';

  @override
  String get roleManagement => '管理';

  @override
  String get roleHQStaff => '總部員工';

  @override
  String get roleSupervisor => '主管';

  @override
  String get roleCashier => '收銀員';

  @override
  String get roleStaff => '員工';

  @override
  String get searchOrderPoClient => '搜尋訂單、採購單、客戶…';

  @override
  String get tabDashboard => '儀表板';

  @override
  String get tabList => '列表';

  @override
  String get nothingHere => '暫無資料';

  @override
  String get shipmentUpdated => '出貨已更新';

  @override
  String get shipmentTitle => '出貨';

  @override
  String shipmentNumber(int id) {
    return '出貨 #$id';
  }

  @override
  String boxesCount(int count) {
    return '$count 箱';
  }

  @override
  String get monitorPacking => '裝箱中';

  @override
  String get monitorPackedAwaitingCourier => '已裝箱 — 待快遞取件';

  @override
  String get monitorShipped => '已出貨';

  @override
  String get monitorCompletedRecent => '已完成（近期）';

  @override
  String get batchPack => '批次裝箱';

  @override
  String get courierPickup => '快遞取件';

  @override
  String get workflowPickPack => '揀貨與裝箱';

  @override
  String get workflowPickPackSub => '掃描品項並確認箱數';

  @override
  String get workflowCourier => '快遞資訊';

  @override
  String get workflowCourierSub => '快遞公司、追蹤號碼與送達日期';

  @override
  String get workflowHandoff => '交付簽收';

  @override
  String get workflowHandoffUploaded => '已上傳簽收單';

  @override
  String get workflowHandoffUploadShipped => '上傳簽收單';

  @override
  String get workflowHandoffUploadAndShip => '上傳簽收單並標記已出貨';

  @override
  String get saveDetails => '儲存資訊';

  @override
  String get batchPacking => '批次裝箱';

  @override
  String get packingQueueComplete => '裝箱佇列已完成';

  @override
  String get noShipmentsInQueue => '佇列中沒有出貨單';

  @override
  String get skipThisShipment => '跳過此出貨單';

  @override
  String get startPacking => '開始裝箱';

  @override
  String get shipmentStatusAssigned => '已分配';

  @override
  String get shipmentStatusPacking => '裝箱中';

  @override
  String get shipmentStatusPacked => '已裝箱';

  @override
  String get shipmentStatusShipped => '已出貨';

  @override
  String get shipmentStatusCompleted => '已完成';

  @override
  String get filterPendingApproval => '待審批';

  @override
  String get filterAssignShipment => '分配出貨';

  @override
  String get filterAwaitingPayment => '待付款';

  @override
  String get filterCompleted => '已完成';

  @override
  String get filterRejected => '已拒絕';

  @override
  String get filterDeleted => '已刪除';

  @override
  String get wholesaleStatusRejected => '已拒絕';

  @override
  String get wholesaleStatusDeleted => '已刪除';

  @override
  String get wholesaleStatusCompleted => '已完成';

  @override
  String get wholesaleStatusPendingOrderConfirmation => '待訂單確認';

  @override
  String get wholesaleStatusPendingPacking => '待裝箱';

  @override
  String get wholesaleStatusInTransit => '運送中';

  @override
  String get wholesaleStatusPendingInvoice => '待發送發票';

  @override
  String get wholesaleStatusPendingPayment => '待收款確認';

  @override
  String get wholesaleStatusPendingApproval => '待審批';

  @override
  String get wholesaleStatusAssignShipment => '分配出貨';

  @override
  String get wholesaleStatusApproved => '已核准';

  @override
  String get posFilterPending => '待處理';

  @override
  String get posFilterPaid => '已付款';

  @override
  String get posFilterPickedUp => '已取貨';

  @override
  String get posFilterCancelled => '已取消';

  @override
  String get takePhoto => '拍照';

  @override
  String get chooseFromGallery => '從相簿選擇';

  @override
  String get chooseFile => '選擇檔案';

  @override
  String get rejectOrder => '拒絕訂單';

  @override
  String get rejectReason => '原因';

  @override
  String get reject => '拒絕';

  @override
  String get noDocumentsYet => '尚無文件';

  @override
  String get uploadPoAttachment => '上傳採購單附件';

  @override
  String get assigned => '已分配';

  @override
  String get move => '移動';

  @override
  String get remove => '移除';

  @override
  String get skip => '跳過';

  @override
  String get emailSkipped => '已跳過郵件';

  @override
  String get emailSent => '郵件已發送';

  @override
  String get resubmit => '重新提交';

  @override
  String get selectStore => '選擇門店';

  @override
  String get assignByDefaults => '依預設分配';

  @override
  String get changeAssignment => '變更分配';

  @override
  String get regenerateOrderConfirmationPdf => '重新產生訂單確認 PDF';

  @override
  String linesCount(int count) {
    return '$count 行';
  }

  @override
  String get generateInvoice => '產生發票';

  @override
  String orderTotal(String amount) {
    return '訂單總額：$amount';
  }

  @override
  String proofTotal(String amount) {
    return '憑證總額：$amount';
  }

  @override
  String get uploadPaymentProof => '上傳付款憑證';

  @override
  String get confirmPaymentReceived => '確認已收款';

  @override
  String get paymentConfirmed => '收款已確認';

  @override
  String get moveReassign => '移動 / 重新分配';

  @override
  String moveFrom(String store) {
    return '從 $store';
  }

  @override
  String get skipEmail => '跳過郵件';

  @override
  String get loadReport => '載入報表';

  @override
  String get posRevenue => 'POS 營收';

  @override
  String posOrdersCount(int count) {
    return 'POS 訂單：$count';
  }

  @override
  String get allStores => '全部門店';

  @override
  String get settingsSaved => '設定已儲存';

  @override
  String get saveSettings => '儲存設定';

  @override
  String get createWholesaleOrder => '建立批發訂單';

  @override
  String get addAtLeastOneProduct => '請至少新增一項產品';

  @override
  String get companyAddress => '公司地址';

  @override
  String get sourceClientPo => '客戶採購單';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceEmail => '電郵';

  @override
  String get sourceNa => '不適用';

  @override
  String get lineItems => '訂單行';

  @override
  String unitPrice(String amount) {
    return '單價：$amount';
  }

  @override
  String poAttachments(int count) {
    return '採購單附件（$count）';
  }

  @override
  String get createOrder => '建立訂單';

  @override
  String get deliveryLocations => '送貨地點';

  @override
  String get auditLog => '審計日誌';

  @override
  String get registerDevice => '註冊設備';

  @override
  String get register => '註冊';

  @override
  String get newCategory => '新分類';

  @override
  String get newSector => '新部門';

  @override
  String get newStore => '新商店';

  @override
  String get warehouse => '倉庫';

  @override
  String get receive => '收貨';

  @override
  String get markPaid => '標記已付款';

  @override
  String get markComplete => '標記完成';

  @override
  String get cancelOrder => '取消訂單？';

  @override
  String get cancelOrderAction => '取消訂單';

  @override
  String get courierDetails => '快遞資訊';

  @override
  String get courierDetailsHint => '輸入快遞與追蹤資訊。輸入時會顯示建議選項。';

  @override
  String get courierHint => '輸入或從建議中選擇';

  @override
  String get trackingNumber => '追蹤號碼';

  @override
  String get deliveryProofLocked => '已上傳交付證明 — 快遞資訊已鎖定。';

  @override
  String shipmentProgress(int current, int total) {
    return '出貨 $current / $total';
  }

  @override
  String get markShipped => '標記已出貨';

  @override
  String get deliveryHandoffHint => '快遞取件時，請上傳簽收單並標記為已出貨。';

  @override
  String get name => '名稱';

  @override
  String get back => '返回';

  @override
  String get no => '否';

  @override
  String get product => '產品';

  @override
  String get quantity => '數量';

  @override
  String get notes => '備註';

  @override
  String get phone => '電話';

  @override
  String get contact => '聯絡人';

  @override
  String get sector => '部門';

  @override
  String qtyTimes(String qty, String price) {
    return '數量 $qty × $price';
  }

  @override
  String get packShipment => '裝箱出貨';

  @override
  String packOrder(String order) {
    return '裝箱 $order';
  }

  @override
  String get manualBarcode => '手動條碼';

  @override
  String get nextConfirmBoxes => '下一步 — 確認箱數';

  @override
  String get confirmBoxes => '確認箱數';

  @override
  String get finishPacking => '完成裝箱';

  @override
  String get products => '產品';

  @override
  String get boxes => '箱數';

  @override
  String expectedBoxes(String qty, int count) {
    return '數量 $qty · 預期箱數 $count';
  }

  @override
  String get deliveryLocation => '送貨地點';

  @override
  String get orderChannel => '訂單來源';

  @override
  String get poNumber => '採購單號';

  @override
  String get poDate => '採購單日期 (YYYY-MM-DD)';

  @override
  String get paymentTerms => '付款條件';

  @override
  String get shippingFee => '運費';

  @override
  String get paymentProofDetails => '付款憑證詳情';

  @override
  String get amount => '金額';

  @override
  String get transferDate => '轉帳日期';

  @override
  String get transferredToAccount => '轉入帳戶';

  @override
  String get saveAndUploadProof => '儲存並上傳憑證';

  @override
  String get orderConfirmation => '訂單確認';

  @override
  String get rejectedSection => '已拒絕';

  @override
  String get deliveryCompleteEmail => '送達完成郵件';

  @override
  String get invoice => '發票';

  @override
  String get assignLinesHint => '將所有訂單行分配至門店，然後確認分配以核准此訂單。';

  @override
  String get assignLinesHintStaged => '將訂單行分配至門店。綠色門店標籤可完全滿足待分配數量；橙色可滿足部分。';

  @override
  String get stageForStore => '暫存至門店';

  @override
  String get assignPendingQty => '分配待處理數量';

  @override
  String get sendDeliveryCompleteEmail => '發送送達完成郵件';

  @override
  String get resendDeliveryCompleteEmail => '重新發送送達完成郵件';

  @override
  String get sendInvoiceEmail => '發送發票郵件';

  @override
  String get resendInvoiceEmail => '重新發送發票郵件';

  @override
  String get skipReasonRequired => '跳過此郵件必須填寫原因';

  @override
  String get shipmentsAfterAssignment => '門店分配後，出貨單將顯示於此。';

  @override
  String get todayPosRevenue => '今日 POS 營收';

  @override
  String get lowStockItems => '低庫存品項';

  @override
  String get pendingRestocks => '待處理補貨';

  @override
  String get pendingWholesaleOrders => '待處理批發訂單';

  @override
  String get companyName => '公司名稱';

  @override
  String get address => '地址';

  @override
  String get city => '城市';

  @override
  String get postcode => '郵遞區號';

  @override
  String get telephone => '電話';

  @override
  String get email => '電郵';

  @override
  String get paymentInfo => '付款資訊';

  @override
  String get shipmentCouriersField => '出貨快遞公司';

  @override
  String get deviceCode => '設備代碼';

  @override
  String get deviceName => '設備名稱';

  @override
  String get currencyCode => '貨幣代碼';

  @override
  String get rateToGbp => '兌 GBP 匯率';

  @override
  String get addCurrencyRate => '新增匯率';

  @override
  String rateLabel(String rate) {
    return '匯率：$rate';
  }

  @override
  String get adjustStock => '調整庫存';

  @override
  String adjustStockTitle(String name) {
    return '調整 $name';
  }

  @override
  String get reason => '原因';

  @override
  String get searchProducts => '搜尋產品';

  @override
  String get firstName => '名字';

  @override
  String get lastName => '姓氏';

  @override
  String get newPasswordOptional => '新密碼（選填）';

  @override
  String get rolePosUser => 'POS 使用者';

  @override
  String locationsCount(int count) {
    return '$count 個地點';
  }

  @override
  String storeNumber(int id) {
    return '門店 #$id';
  }

  @override
  String restockNumber(int id) {
    return '補貨 #$id';
  }

  @override
  String get selectCourier => '請選擇快遞公司';

  @override
  String get selectAtLeastOneShipment => '請至少選擇一筆出貨單';

  @override
  String get noCouriersConfigured => '公司設定中未設定快遞公司。';

  @override
  String get selectOrders => '選擇訂單';

  @override
  String get scanDeliveryNote => '掃描簽收單';

  @override
  String get confirmStep => '確認';

  @override
  String noMatchingShipment(String code) {
    return '找不到符合的出貨單：$code';
  }

  @override
  String markedShippedVia(int count, String courier) {
    return '已將 $count 筆出貨標記為已出貨（$courier）';
  }

  @override
  String courierLabel(String name) {
    return '快遞：$name';
  }

  @override
  String shipmentsCountLabel(int count) {
    return '出貨單：$count';
  }

  @override
  String get more => '更多';

  @override
  String get apiServer => 'API 伺服器';

  @override
  String get environment => '環境';

  @override
  String get biometricUnlock => '生物辨識解鎖';

  @override
  String get biometricUnlockSubtitle => '開啟應用程式時需要 Face ID / 指紋';

  @override
  String get startDate => '開始日期 (YYYY-MM-DD)';

  @override
  String get endDate => '結束日期 (YYYY-MM-DD)';

  @override
  String get toStore => '目標門店';

  @override
  String get stepCreated => '已建立';

  @override
  String get stepOrderConfirmation => '訂單確認';

  @override
  String get stepStartShipment => '開始出貨';

  @override
  String get stepFinishShipment => '完成出貨';

  @override
  String get stepInvoiceEmail => '發票郵件';

  @override
  String get stepPaymentConfirmation => '收款確認';

  @override
  String get stepComplete => '完成';

  @override
  String get total => '總計';

  @override
  String get ref => '參考號';

  @override
  String get channel => '來源';

  @override
  String get rejection => '拒絕原因';

  @override
  String get unassigned => '未分配';

  @override
  String qtyAssigned(String qty, String assigned) {
    return '數量 $qty · 已分配 $assigned';
  }

  @override
  String get staged => '暫存';

  @override
  String get newUser => '新增使用者';

  @override
  String get editUser => '編輯使用者';

  @override
  String get staff => '員工';

  @override
  String get subtotal => '小計';

  @override
  String get discount => '折扣';

  @override
  String get posOrder => 'POS 訂單';

  @override
  String get confirmAllocationApprove => '確認分配並核准';

  @override
  String get confirmAllocation => '確認分配';

  @override
  String get allLinesAssigned => '所有訂單行已分配至門店。';

  @override
  String get changeAssignmentWhilePacking => '出貨單仍在分配/裝箱階段時，可變更分配。';

  @override
  String get orderConfirmationEmail => '訂單確認郵件';

  @override
  String get sendOrderConfirmationEmail => '發送訂單確認郵件';

  @override
  String get resendOrderConfirmationEmail => '重新發送訂單確認郵件';

  @override
  String get paymentConfirmationSection => '收款確認';

  @override
  String get actionNeeded => '需要操作';

  @override
  String get forceComplete => '強制完成';

  @override
  String get next => '下一步';

  @override
  String get confirmPickup => '確認取件';

  @override
  String get scanHint => '訂單號、採購單、參考號…';

  @override
  String selectedOrder(String order) {
    return '已選擇 $order';
  }

  @override
  String totalBoxes(int count) {
    return '總箱數：$count';
  }

  @override
  String get saveChanges => '儲存變更';

  @override
  String get createUser => '建立使用者';

  @override
  String get required => '必填';

  @override
  String get send => '發送';

  @override
  String get toField => '收件人';

  @override
  String get ccField => '副本';

  @override
  String get bccField => '密件副本';

  @override
  String get subjectField => '主旨';

  @override
  String get messageField => '內容';

  @override
  String get attachments => '附件';

  @override
  String get focusMode => '專注';

  @override
  String get focusModeTooltip => '專注模式 — 掃描時螢幕保持開啟';

  @override
  String get scanStep => '1/2 掃描';

  @override
  String get boxesStep => '2/2 箱數';

  @override
  String needQtyBoxes(String qty, String boxes) {
    return '需要 $qty · 箱數 $boxes';
  }

  @override
  String get turnPhoneNext => '轉動或移動手機至下一個產品';

  @override
  String get phoneTurnedNext => '手機已轉向下一個產品';

  @override
  String get pauseComplete => '暫停完成';

  @override
  String pauseForSeconds(int seconds) {
    return '移動時暫停 $seconds 秒';
  }

  @override
  String reasonPrefix(String reason) {
    return '原因：$reason';
  }

  @override
  String skippedAt(String date) {
    return '跳過於 $date';
  }

  @override
  String skippedBy(String name) {
    return '跳過者 $name';
  }

  @override
  String previouslySentAt(String date) {
    return '先前發送於 $date';
  }

  @override
  String get noPaymentProof => '無付款憑證';

  @override
  String get forceConfirmPayment => '強制確認收款';

  @override
  String get noPaymentProofWarning => '尚未上傳付款憑證。確定要在沒有憑證的情況下確認嗎？';

  @override
  String get forceConfirmWarning => '這將在未符合憑證總額的情況下標記為已收款。僅在確定款項已收齊時使用。';

  @override
  String get confirmPaymentQuestion => '確認此訂單已收到款項？';

  @override
  String get proofShortfallHint => '憑證總額低於訂單總額。收款確認後將無法再上傳憑證。';

  @override
  String get snackSelectStore => '請選擇門店';

  @override
  String get snackShipmentPacked => '該門店出貨單已裝箱或已出貨';

  @override
  String get snackLineStaged => '訂單行已暫存待分配';

  @override
  String get snackDefaultStaged => '預設分配已暫存 — 準備好後請確認';

  @override
  String get snackAssignAllLines => '確認前請分配所有訂單行';

  @override
  String get snackOrderApproved => '訂單已核准並分配';

  @override
  String get snackAllocationConfirmedContinue => '分配已確認 — 請發送訂單確認郵件或跳過以繼續';

  @override
  String get snackAssignmentRemoved => '分配已移除';

  @override
  String get snackAssignmentMoved => '分配已移動';

  @override
  String get snackPaymentProofUploaded => '付款憑證已上傳';

  @override
  String get snackPaymentProofAutoConfirmed => '付款憑證已上傳，收款已自動確認。';

  @override
  String get lineAssigned => '訂單行已分配';

  @override
  String get assignedByDefaults => '已依預設分配';

  @override
  String get orderResubmitted => '訂單已重新提交';

  @override
  String get orderConfirmationRegenerated => '訂單確認已重新產生';

  @override
  String get invoiceGenerated => '發票已產生';

  @override
  String qtyLabel(String qty) {
    return '數量 $qty';
  }

  @override
  String filesSelected(int count) {
    return '已選擇 $count 個檔案';
  }

  @override
  String get enterValidAmount => '請輸入有效金額';

  @override
  String get selectTransferDate => '請選擇轉帳日期';

  @override
  String get selectDestinationAccount => '請選擇目標帳戶';

  @override
  String get role => '角色';

  @override
  String get newClient => '新增客戶';

  @override
  String get editClient => '編輯客戶';

  @override
  String get findNextItemToScan => '尋找下一個要掃描的品項';

  @override
  String get active => '啟用';

  @override
  String get inactive => '停用';

  @override
  String get po => '採購單';

  @override
  String get resend => '重新發送';

  @override
  String get resendEmail => '重新發送郵件';

  @override
  String get sendOrderConfirmationEmailDescription => '向客戶發送附帶附件的訂單確認郵件。';

  @override
  String get sendDeliveryCompleteEmailDescription => '發送附帶已簽收送貨單的送貨完成郵件。';

  @override
  String get sendInvoiceEmailDescription => '發送附帶發票及可選送貨文件的發票郵件。';

  @override
  String get emailRecipientsRequired => '至少需要一個收件人電郵';

  @override
  String invalidEmailAddress(String email) {
    return '無效電郵：$email';
  }

  @override
  String get selectAtLeastOneAttachment => '請至少選擇一個附件';

  @override
  String get sendSkippedEmailNow => '此郵件先前已跳過，您現在仍可發送。';

  @override
  String attachmentsList(String list) {
    return '附件：$list';
  }

  @override
  String filesList(String list) {
    return '檔案：$list';
  }

  @override
  String get invoiceDeliveryDocsOptional => '發票郵件中的送貨單與送貨證明為可選。';

  @override
  String get emailRecipientsHint => 'email@example.com, another@example.com';

  @override
  String paymentProofNumber(int id) {
    return '付款憑證 #$id';
  }

  @override
  String get productNotFound => '找不到產品';

  @override
  String productNotFoundDetail(String code) {
    return '條碼「$code」與此出貨單上的任何品項不符。';
  }

  @override
  String get quantityAlreadyComplete => '數量已完成';

  @override
  String quantityAlreadyCompleteDetail(
    String product,
    String scanned,
    String expected,
  ) {
    return '$product 已掃描完成（$scanned/$expected）。請掃描其他品項。';
  }

  @override
  String scanProgress(String product, String scanned, String expected) {
    return '$product：$scanned / $expected';
  }

  @override
  String get biometricEnableReason => '啟用 POS 管理系統的生物辨識解鎖';

  @override
  String get biometricUnlockReason => '解鎖 POS 管理系統';

  @override
  String get restockStatusInitiated => '已發起';

  @override
  String get restockStatusInTransit => '運送中';

  @override
  String get restockStatusReceived => '已收到';

  @override
  String get markedShippedSnack => '已標記出貨';

  @override
  String get shipmentMarkedAwaitProof => '出貨單已標記出貨。收到已簽收送貨單後請上傳。';
}
