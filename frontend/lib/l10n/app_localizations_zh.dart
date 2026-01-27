// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'POS 系統';

  @override
  String get loginTitle => '德靈公司 POS v1.0';

  @override
  String get enterPIN => '輸入 PIN';

  @override
  String get signIn => '登入';

  @override
  String get signingIn => '登入中...';

  @override
  String get username => '使用者名稱';

  @override
  String get password => '密碼';

  @override
  String get email => 'Email';

  @override
  String get pin => 'PIN';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get delete => '刪除';

  @override
  String get edit => '編輯';

  @override
  String get add => '新增';

  @override
  String get update => '更新';

  @override
  String get close => '關閉';

  @override
  String get error => '錯誤';

  @override
  String get confirm => '確認';

  @override
  String get search => '搜尋';

  @override
  String get loading => '載入中...';

  @override
  String get noData => '找不到資料';

  @override
  String get sync => '同步';

  @override
  String get syncUsers => '同步使用者';

  @override
  String get syncing => '同步中...';

  @override
  String get loginWithUsernamePassword => '使用使用者名稱/密碼登入';

  @override
  String get noUsersAvailable => '沒有可用的使用者';

  @override
  String get pleaseSyncWithServerFirst => '請先與伺服器同步';

  @override
  String get invalidPIN => 'PIN 無效';

  @override
  String get loginFailed => '登入失敗';

  @override
  String pinMustBeDigits(int count) {
    return 'PIN 必須恰好為 $count 位數字';
  }

  @override
  String get newOrder => '新訂單';

  @override
  String get searchOrder => '搜尋訂單';

  @override
  String get inventory => '庫存';

  @override
  String get userManagement => '使用者管理';

  @override
  String get report => '報表';

  @override
  String get settings => '設定';

  @override
  String get logout => '登出';

  @override
  String get areYouSureLogout => '您確定要登出嗎？';

  @override
  String get dataSyncedSuccessfully => '資料同步成功';

  @override
  String get searchProducts => '依名稱、條碼或 SKU 搜尋產品...';

  @override
  String noProductsFound(String query) {
    return '找不到「$query」的產品';
  }

  @override
  String noProductsInCategory(String category) {
    return '分類「$category」中沒有產品';
  }

  @override
  String get noProductsAvailable => '沒有可用的產品';

  @override
  String get clearFilters => '清除篩選';

  @override
  String get scanBarcode => '掃描條碼';

  @override
  String get addedToCart => '已加入購物車';

  @override
  String addedWeightToCart(double weight) {
    return '已將 ${weight}g 加入購物車';
  }

  @override
  String productAddedToCart(String name) {
    return '產品「$name」已加入購物車';
  }

  @override
  String get enterWeight => '輸入重量';

  @override
  String get weightG => '重量 (g)';

  @override
  String get quantity => '數量';

  @override
  String get inventoryManagement => '庫存管理';

  @override
  String get currentStock => '目前庫存';

  @override
  String get incomingStock => '進貨中';

  @override
  String storeID(int id) {
    return '商店 ID: $id';
  }

  @override
  String get noInventoryData => '沒有庫存資料';

  @override
  String get noIncomingStockOrders => '沒有進貨訂單';

  @override
  String updateStock(String name) {
    return '更新庫存: $name';
  }

  @override
  String get reasonOptional => '原因（選填）';

  @override
  String get reasonPlaceholder => '例如：手動調整、收到庫存';

  @override
  String get stockUpdatedSuccessfully => '庫存已成功更新';

  @override
  String failedToUpdateStock(String error) {
    return '無法更新庫存: $error';
  }

  @override
  String get confirmReceipt => '確認收貨';

  @override
  String get confirmReceiptMessage => '您確定要確認此庫存已到達嗎？這將更新庫存數量。';

  @override
  String get stockReceiptConfirmed => '庫存收貨已確認';

  @override
  String failedToConfirmReceipt(String error) {
    return '無法確認收貨: $error';
  }

  @override
  String get orderHistory => '訂單歷史';

  @override
  String get searchByOrderTotalDate => '依訂單編號、總額或日期搜尋';

  @override
  String get noOrdersFound => '找不到訂單';

  @override
  String orderNumberHash(String number) {
    return 'Order #$number';
  }

  @override
  String orderNumber(String number) {
    return '訂單編號: $number';
  }

  @override
  String date(String date) {
    return '日期: $date';
  }

  @override
  String viewReceipt(String number) {
    return '查看訂單 #$number 的收據';
  }

  @override
  String get comingSoon => '即將推出';

  @override
  String get inventoryManagementComingSoon => '庫存管理（即將推出）';

  @override
  String get userManagementComingSoon => '使用者管理（即將推出）';

  @override
  String get reportsComingSoon => '報表（即將推出）';

  @override
  String get all => '全部';

  @override
  String get product => '產品';

  @override
  String get store => '商店';

  @override
  String qty(String quantity) {
    return '數量: $quantity';
  }

  @override
  String weightDisplay(String weight) {
    return '${weight}g';
  }

  @override
  String syncedUsers(int count) {
    return '已成功同步 $count 位使用者';
  }

  @override
  String get noUsersFoundForDevice => '伺服器上找不到此裝置的使用者。';

  @override
  String syncFailed(String error) {
    return '同步失敗: $error';
  }

  @override
  String get deviceCodeNotAvailable => '裝置代碼不可用。請先註冊裝置。';

  @override
  String get refresh => '重新整理';

  @override
  String get checkout => '結帳';

  @override
  String get subtotal => '小計';

  @override
  String get discount => '折扣';

  @override
  String get total => '總計';

  @override
  String get processPayment => '處理付款';

  @override
  String get orderReceipt => '訂單收據';

  @override
  String get print => '列印';

  @override
  String get printInternalAuditNote => 'Print Audit Note';

  @override
  String get printInvoice => 'Print Invoice';

  @override
  String get printCustomerReceipt => 'Print receipt';

  @override
  String get printAll => 'Print All';

  @override
  String get markPaid => '標記已付款';

  @override
  String get orderCreatedSuccessfully => '訂單已成功建立';

  @override
  String get storeNotSelected => '未選擇商店';

  @override
  String get userNotAuthenticated => '使用者未驗證';

  @override
  String get status => '狀態';

  @override
  String get reprint => '重新列印';

  @override
  String get tracking => '追蹤';

  @override
  String get unknownProduct => '未知產品';

  @override
  String get language => '語言';

  @override
  String get printerSettings => '印表機設定';

  @override
  String get connectionType => '連線類型';

  @override
  String get network => '網路';

  @override
  String get bluetooth => '藍芽';

  @override
  String get usb => 'USB';

  @override
  String get networkSettings => '網路設定';

  @override
  String get bluetoothSettings => '藍牙設定';

  @override
  String get usbSettings => 'USB 設定';

  @override
  String get printerIPAddress => '印表機 IP 位址';

  @override
  String get printerPort => '連接埠';

  @override
  String get usbSerialPort => 'USB 序列埠';

  @override
  String get usbSerialPortHint =>
      '例如：/dev/tty.usbserial-* 或 /dev/cu.usbserial-*';

  @override
  String get scanDevices => '掃描裝置';

  @override
  String get scanning => '掃描中...';

  @override
  String get noBluetoothDevicesFound => '找不到藍牙裝置';

  @override
  String get testPrinter => '測試印表機';

  @override
  String get saveSettings => '儲存設定';

  @override
  String get settingsSavedSuccessfully => '設定已成功儲存';

  @override
  String get noUsbPrintersFound => '找不到 USB 印表機。請確認印表機已連接。';

  @override
  String get orderPickup => 'Order Pickup';

  @override
  String get scanOrderQRCode => 'Scan Order QR Code';

  @override
  String get scanQRCodeToConfirmPickup =>
      'Scan a QR code to confirm the pickup';

  @override
  String get enterItManually => 'Enter it manually';

  @override
  String get enterOrderNumber => 'Enter Order Number';

  @override
  String get scanOrEnterOrderNumber => 'Scan QR code or enter order number';

  @override
  String get useBarcodeScannerOrTypeManually =>
      'Use a barcode scanner or type the order number manually';

  @override
  String get orderDetails => 'Order Details';

  @override
  String get orderInformation => 'Order Information';

  @override
  String get orderItems => 'Order Items';

  @override
  String get createdAt => 'Created At';

  @override
  String get paidAt => 'Paid At';

  @override
  String get completedAt => 'Completed At';

  @override
  String get pickedUpAt => 'Picked Up At';

  @override
  String get printReceipts => 'Print Receipts';

  @override
  String get noItemsFound => 'No items found';

  @override
  String get confirmPickup => 'Confirm Pickup';

  @override
  String get cancelOrder => 'Cancel Order';

  @override
  String get cancelOrderConfirmation =>
      'Are you sure you want to cancel this order?';

  @override
  String get profile => 'Profile';

  @override
  String get userInfo => 'User Information';

  @override
  String get firstName => 'First Name';

  @override
  String get lastName => 'Last Name';

  @override
  String get role => 'Role';

  @override
  String get profileIcon => 'Profile Icon';

  @override
  String get changeIcon => 'Change Icon';

  @override
  String get changePIN => 'Change PIN';

  @override
  String get pinInfo => 'Enter your current PIN and a new PIN to change it.';

  @override
  String get currentPIN => 'Current PIN';

  @override
  String get currentPINRequired => 'Current PIN is required';

  @override
  String get newPIN => 'New PIN';

  @override
  String get newPINRequired => 'New PIN is required';

  @override
  String get confirmPIN => 'Confirm New PIN';

  @override
  String get pinMismatch => 'PINs do not match';

  @override
  String get pinMinLength => 'PIN must be at least 4 characters';

  @override
  String get pinUpdated => 'PIN updated successfully';

  @override
  String get iconUpdated => 'Icon updated successfully';

  @override
  String get generateFromColors => 'Generate from Colors';

  @override
  String get uploadImage => 'Upload Image';

  @override
  String get backgroundColor => 'Background Color';

  @override
  String get textColor => 'Text Color';

  @override
  String get selectImage => 'Select Image';

  @override
  String get updatePIN => 'Update PIN';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appTitle => 'POS 系统';

  @override
  String get loginTitle => '德靈公司 POS v1.0';

  @override
  String get enterPIN => '输入 PIN';

  @override
  String get signIn => '登录';

  @override
  String get signingIn => '登录中...';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get email => '电子邮件';

  @override
  String get pin => 'PIN';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get add => '添加';

  @override
  String get update => '更新';

  @override
  String get close => '关闭';

  @override
  String get error => '错误';

  @override
  String get confirm => '确认';

  @override
  String get search => '搜索';

  @override
  String get loading => '加载中...';

  @override
  String get noData => '未找到数据';

  @override
  String get sync => '同步';

  @override
  String get syncUsers => '同步用户';

  @override
  String get syncing => '同步中...';

  @override
  String get loginWithUsernamePassword => '使用用户名/密码登录';

  @override
  String get noUsersAvailable => '没有可用的用户';

  @override
  String get pleaseSyncWithServerFirst => '请先与服务器同步';

  @override
  String get invalidPIN => 'PIN 无效';

  @override
  String get loginFailed => '登录失败';

  @override
  String pinMustBeDigits(int count) {
    return 'PIN 必须恰好为 $count 位数字';
  }

  @override
  String get newOrder => '新订单';

  @override
  String get searchOrder => '搜索订单';

  @override
  String get inventory => '库存';

  @override
  String get userManagement => '用户管理';

  @override
  String get report => '报表';

  @override
  String get settings => '设置';

  @override
  String get logout => '登出';

  @override
  String get areYouSureLogout => '您确定要登出吗？';

  @override
  String get dataSyncedSuccessfully => '数据同步成功';

  @override
  String get searchProducts => '按名称、条码或 SKU 搜索产品...';

  @override
  String noProductsFound(String query) {
    return '找不到「$query」的产品';
  }

  @override
  String noProductsInCategory(String category) {
    return '分类「$category」中没有产品';
  }

  @override
  String get noProductsAvailable => '没有可用的产品';

  @override
  String get clearFilters => '清除筛选';

  @override
  String get scanBarcode => '扫描条码';

  @override
  String get addedToCart => '已加入购物车';

  @override
  String addedWeightToCart(double weight) {
    return '已将 ${weight}g 加入购物车';
  }

  @override
  String productAddedToCart(String name) {
    return '产品「$name」已加入购物车';
  }

  @override
  String get enterWeight => '输入重量';

  @override
  String get weightG => '重量 (g)';

  @override
  String get quantity => '数量';

  @override
  String get inventoryManagement => '库存管理';

  @override
  String get currentStock => '当前库存';

  @override
  String get incomingStock => '进货中';

  @override
  String storeID(int id) {
    return '商店 ID: $id';
  }

  @override
  String get noInventoryData => '没有库存数据';

  @override
  String get noIncomingStockOrders => '没有进货订单';

  @override
  String updateStock(String name) {
    return '更新库存: $name';
  }

  @override
  String get reasonOptional => '原因（选填）';

  @override
  String get reasonPlaceholder => '例如：手动调整、收到库存';

  @override
  String get stockUpdatedSuccessfully => '库存已成功更新';

  @override
  String failedToUpdateStock(String error) {
    return '无法更新库存: $error';
  }

  @override
  String get confirmReceipt => '确认收货';

  @override
  String get confirmReceiptMessage => '您确定要确认此库存已到达吗？这将更新库存数量。';

  @override
  String get stockReceiptConfirmed => '库存收货已确认';

  @override
  String failedToConfirmReceipt(String error) {
    return '无法确认收货: $error';
  }

  @override
  String get orderHistory => '订单历史';

  @override
  String get searchByOrderTotalDate => '按订单编号、总额或日期搜索';

  @override
  String get noOrdersFound => '找不到订单';

  @override
  String orderNumber(String number) {
    return '订单编号: $number';
  }

  @override
  String date(String date) {
    return '日期: $date';
  }

  @override
  String viewReceipt(String number) {
    return '查看订单 #$number 的收据';
  }

  @override
  String get comingSoon => '即将推出';

  @override
  String get inventoryManagementComingSoon => '库存管理（即将推出）';

  @override
  String get userManagementComingSoon => '用户管理（即将推出）';

  @override
  String get reportsComingSoon => '报表（即将推出）';

  @override
  String get all => '全部';

  @override
  String get product => '产品';

  @override
  String get store => '商店';

  @override
  String qty(String quantity) {
    return '数量: $quantity';
  }

  @override
  String weightDisplay(String weight) {
    return '${weight}g';
  }

  @override
  String syncedUsers(int count) {
    return '已成功同步 $count 位用户';
  }

  @override
  String get noUsersFoundForDevice => '服务器上找不到此设备的用户。';

  @override
  String syncFailed(String error) {
    return '同步失败: $error';
  }

  @override
  String get deviceCodeNotAvailable => '设备代码不可用。请先注册设备。';

  @override
  String get refresh => '刷新';

  @override
  String get checkout => '结账';

  @override
  String get subtotal => '小计';

  @override
  String get discount => '折扣';

  @override
  String get total => '总计';

  @override
  String get processPayment => '处理付款';

  @override
  String get orderReceipt => '订单收据';

  @override
  String get print => '打印';

  @override
  String get printInternalAuditNote => '打印审计单';

  @override
  String get printInvoice => '打印发票';

  @override
  String get printCustomerReceipt => '打印收据';

  @override
  String get printAll => '打印全部';

  @override
  String get markPaid => '标记已付款';

  @override
  String get orderCreatedSuccessfully => '订单已成功创建';

  @override
  String get storeNotSelected => '未选择商店';

  @override
  String get userNotAuthenticated => '用户未验证';

  @override
  String get status => '状态';

  @override
  String get reprint => '重新打印';

  @override
  String get tracking => '跟踪';

  @override
  String get unknownProduct => '未知产品';

  @override
  String get language => '语言';

  @override
  String get printerSettings => '打印机设置';

  @override
  String get connectionType => '连接类型';

  @override
  String get network => '网络';

  @override
  String get bluetooth => '蓝牙';

  @override
  String get usb => 'USB';

  @override
  String get networkSettings => '网络设置';

  @override
  String get bluetoothSettings => '蓝牙设置';

  @override
  String get usbSettings => 'USB 设置';

  @override
  String get printerIPAddress => '打印机 IP 地址';

  @override
  String get printerPort => '端口';

  @override
  String get usbSerialPort => 'USB 串口';

  @override
  String get usbSerialPortHint =>
      '例如：/dev/tty.usbserial-* 或 /dev/cu.usbserial-*';

  @override
  String get scanDevices => '扫描设备';

  @override
  String get scanning => '扫描中...';

  @override
  String get noBluetoothDevicesFound => '未找到蓝牙设备';

  @override
  String get testPrinter => '测试打印机';

  @override
  String get saveSettings => '保存设置';

  @override
  String get settingsSavedSuccessfully => '设置已成功保存';

  @override
  String get noUsbPrintersFound => '未找到 USB 打印机。请确保打印机已连接。';

  @override
  String get orderPickup => '订单取货';

  @override
  String get scanOrderQRCode => '扫描订单 QR 码';

  @override
  String get scanQRCodeToConfirmPickup => '扫描二维码以确认取货';

  @override
  String get enterItManually => '手动输入';

  @override
  String get enterOrderNumber => '输入订单号码';

  @override
  String get scanOrEnterOrderNumber => '扫描 QR 码或输入订单号码';

  @override
  String get useBarcodeScannerOrTypeManually => '使用条码扫描器或手动输入订单号码';

  @override
  String get orderDetails => '订单详情';

  @override
  String get orderInformation => '订单信息';

  @override
  String get orderItems => '订单项目';

  @override
  String get createdAt => '创建时间';

  @override
  String get paidAt => '付款时间';

  @override
  String get completedAt => '完成时间';

  @override
  String get pickedUpAt => '取货时间';

  @override
  String get printReceipts => '打印收据';

  @override
  String get noItemsFound => '未找到项目';

  @override
  String get confirmPickup => '确认取货';

  @override
  String get cancelOrder => '取消订单';

  @override
  String get cancelOrderConfirmation => '您确定要取消此订单吗？';

  @override
  String get profile => '个人资料';

  @override
  String get userInfo => '用户信息';

  @override
  String get firstName => '名字';

  @override
  String get lastName => '姓氏';

  @override
  String get role => '角色';

  @override
  String get profileIcon => '个人资料图标';

  @override
  String get changeIcon => '更改图标';

  @override
  String get changePIN => '更改 PIN';

  @override
  String get pinInfo => '输入您当前的 PIN 和新 PIN 以进行更改。';

  @override
  String get currentPIN => '当前 PIN';

  @override
  String get currentPINRequired => '当前 PIN 是必需的';

  @override
  String get newPIN => '新 PIN';

  @override
  String get newPINRequired => '新 PIN 是必需的';

  @override
  String get confirmPIN => '确认新 PIN';

  @override
  String get pinMismatch => 'PIN 不匹配';

  @override
  String get pinMinLength => 'PIN 必须至少 4 个字符';

  @override
  String get pinUpdated => 'PIN 更新成功';

  @override
  String get iconUpdated => '图标更新成功';

  @override
  String get generateFromColors => '从颜色生成';

  @override
  String get uploadImage => '上传图片';

  @override
  String get backgroundColor => '背景颜色';

  @override
  String get textColor => '文字颜色';

  @override
  String get selectImage => '选择图片';

  @override
  String get updatePIN => '更新 PIN';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'POS 系統';

  @override
  String get loginTitle => '德靈公司 POS v1.0';

  @override
  String get enterPIN => '輸入 PIN';

  @override
  String get signIn => '登入';

  @override
  String get signingIn => '登入中...';

  @override
  String get username => '使用者名稱';

  @override
  String get password => '密碼';

  @override
  String get email => '電子郵件';

  @override
  String get pin => 'PIN';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get delete => '刪除';

  @override
  String get edit => '編輯';

  @override
  String get add => '新增';

  @override
  String get update => '更新';

  @override
  String get close => '關閉';

  @override
  String get error => '錯誤';

  @override
  String get confirm => '確認';

  @override
  String get search => '搜尋';

  @override
  String get loading => '載入中...';

  @override
  String get noData => '找不到資料';

  @override
  String get sync => '同步';

  @override
  String get syncUsers => '同步使用者';

  @override
  String get syncing => '同步中...';

  @override
  String get loginWithUsernamePassword => '使用使用者名稱/密碼登入';

  @override
  String get noUsersAvailable => '沒有可用的使用者';

  @override
  String get pleaseSyncWithServerFirst => '請先與伺服器同步';

  @override
  String get invalidPIN => 'PIN 無效';

  @override
  String get loginFailed => '登入失敗';

  @override
  String pinMustBeDigits(int count) {
    return 'PIN 必須恰好為 $count 位數字';
  }

  @override
  String get newOrder => '新訂單';

  @override
  String get searchOrder => '搜尋訂單';

  @override
  String get inventory => '庫存';

  @override
  String get userManagement => '使用者管理';

  @override
  String get report => '報表';

  @override
  String get settings => '設定';

  @override
  String get logout => '登出';

  @override
  String get areYouSureLogout => '您確定要登出嗎？';

  @override
  String get dataSyncedSuccessfully => '資料同步成功';

  @override
  String get searchProducts => '依名稱、條碼或 SKU 搜尋產品...';

  @override
  String noProductsFound(String query) {
    return '找不到「$query」的產品';
  }

  @override
  String noProductsInCategory(String category) {
    return '分類「$category」中沒有產品';
  }

  @override
  String get noProductsAvailable => '沒有可用的產品';

  @override
  String get clearFilters => '清除篩選';

  @override
  String get scanBarcode => '掃描條碼';

  @override
  String get addedToCart => '已加入購物車';

  @override
  String addedWeightToCart(double weight) {
    return '已將 ${weight}g 加入購物車';
  }

  @override
  String productAddedToCart(String name) {
    return '產品「$name」已加入購物車';
  }

  @override
  String get enterWeight => '輸入重量';

  @override
  String get weightG => '重量 (g)';

  @override
  String get quantity => '數量';

  @override
  String get inventoryManagement => '庫存管理';

  @override
  String get currentStock => '目前庫存';

  @override
  String get incomingStock => '進貨中';

  @override
  String storeID(int id) {
    return '商店 ID: $id';
  }

  @override
  String get noInventoryData => '沒有庫存資料';

  @override
  String get noIncomingStockOrders => '沒有進貨訂單';

  @override
  String updateStock(String name) {
    return '更新庫存: $name';
  }

  @override
  String get reasonOptional => '原因（選填）';

  @override
  String get reasonPlaceholder => '例如：手動調整、收到庫存';

  @override
  String get stockUpdatedSuccessfully => '庫存已成功更新';

  @override
  String failedToUpdateStock(String error) {
    return '無法更新庫存: $error';
  }

  @override
  String get confirmReceipt => '確認收貨';

  @override
  String get confirmReceiptMessage => '您確定要確認此庫存已到達嗎？這將更新庫存數量。';

  @override
  String get stockReceiptConfirmed => '庫存收貨已確認';

  @override
  String failedToConfirmReceipt(String error) {
    return '無法確認收貨: $error';
  }

  @override
  String get orderHistory => '訂單歷史';

  @override
  String get searchByOrderTotalDate => '依訂單編號、總額或日期搜尋';

  @override
  String get noOrdersFound => '找不到訂單';

  @override
  String orderNumber(String number) {
    return '訂單編號: $number';
  }

  @override
  String date(String date) {
    return '日期: $date';
  }

  @override
  String viewReceipt(String number) {
    return '查看訂單 #$number 的收據';
  }

  @override
  String get comingSoon => '即將推出';

  @override
  String get inventoryManagementComingSoon => '庫存管理（即將推出）';

  @override
  String get userManagementComingSoon => '使用者管理（即將推出）';

  @override
  String get reportsComingSoon => '報表（即將推出）';

  @override
  String get all => '全部';

  @override
  String get product => '產品';

  @override
  String get store => '商店';

  @override
  String qty(String quantity) {
    return '數量: $quantity';
  }

  @override
  String weightDisplay(String weight) {
    return '${weight}g';
  }

  @override
  String syncedUsers(int count) {
    return '已成功同步 $count 位使用者';
  }

  @override
  String get noUsersFoundForDevice => '伺服器上找不到此裝置的使用者。';

  @override
  String syncFailed(String error) {
    return '同步失敗: $error';
  }

  @override
  String get deviceCodeNotAvailable => '裝置代碼不可用。請先註冊裝置。';

  @override
  String get refresh => '重新整理';

  @override
  String get checkout => '結帳';

  @override
  String get subtotal => '小計';

  @override
  String get discount => '折扣';

  @override
  String get total => '總計';

  @override
  String get processPayment => '處理付款';

  @override
  String get orderReceipt => '訂單收據';

  @override
  String get print => '列印';

  @override
  String get printInternalAuditNote => '列印審計單';

  @override
  String get printInvoice => '列印發票';

  @override
  String get printCustomerReceipt => '列印收據';

  @override
  String get printAll => '列印全部';

  @override
  String get markPaid => '標記已付款';

  @override
  String get orderCreatedSuccessfully => '訂單已成功建立';

  @override
  String get storeNotSelected => '未選擇商店';

  @override
  String get userNotAuthenticated => '使用者未驗證';

  @override
  String get status => '狀態';

  @override
  String get reprint => '重新列印';

  @override
  String get tracking => '追蹤';

  @override
  String get unknownProduct => '未知產品';

  @override
  String get language => '語言';

  @override
  String get printerSettings => '印表機設定';

  @override
  String get connectionType => '連線類型';

  @override
  String get network => '網路';

  @override
  String get bluetooth => '藍牙';

  @override
  String get usb => 'USB';

  @override
  String get networkSettings => '網路設定';

  @override
  String get bluetoothSettings => '藍牙設定';

  @override
  String get usbSettings => 'USB 設定';

  @override
  String get printerIPAddress => '印表機 IP 位址';

  @override
  String get printerPort => '連接埠';

  @override
  String get usbSerialPort => 'USB 序列埠';

  @override
  String get usbSerialPortHint =>
      '例如：/dev/tty.usbserial-* 或 /dev/cu.usbserial-*';

  @override
  String get scanDevices => '掃描裝置';

  @override
  String get scanning => '掃描中...';

  @override
  String get noBluetoothDevicesFound => '找不到藍牙裝置';

  @override
  String get testPrinter => '測試印表機';

  @override
  String get saveSettings => '儲存設定';

  @override
  String get settingsSavedSuccessfully => '設定已成功儲存';

  @override
  String get noUsbPrintersFound => '找不到 USB 印表機。請確認印表機已連接。';

  @override
  String get orderPickup => '訂單取貨';

  @override
  String get scanOrderQRCode => '掃描訂單 QR 碼';

  @override
  String get scanQRCodeToConfirmPickup => '掃描二維碼以確認取貨';

  @override
  String get enterItManually => '手動輸入';

  @override
  String get enterOrderNumber => '輸入訂單號碼';

  @override
  String get scanOrEnterOrderNumber => '掃描 QR 碼或輸入訂單號碼';

  @override
  String get useBarcodeScannerOrTypeManually => '使用條碼掃描器或手動輸入訂單號碼';

  @override
  String get orderDetails => '訂單詳情';

  @override
  String get orderInformation => '訂單資訊';

  @override
  String get orderItems => '訂單項目';

  @override
  String get createdAt => '建立時間';

  @override
  String get paidAt => '付款時間';

  @override
  String get completedAt => '完成時間';

  @override
  String get pickedUpAt => '取貨時間';

  @override
  String get printReceipts => '列印收據';

  @override
  String get noItemsFound => '找不到項目';

  @override
  String get confirmPickup => '確認取貨';

  @override
  String get cancelOrder => '取消訂單';

  @override
  String get cancelOrderConfirmation => '您確定要取消此訂單嗎？';

  @override
  String get profile => '個人資料';

  @override
  String get userInfo => '用戶資訊';

  @override
  String get firstName => '名字';

  @override
  String get lastName => '姓氏';

  @override
  String get role => '角色';

  @override
  String get profileIcon => '個人資料圖示';

  @override
  String get changeIcon => '更改圖示';

  @override
  String get changePIN => '更改 PIN';

  @override
  String get pinInfo => '輸入您當前的 PIN 和新 PIN 以進行更改。';

  @override
  String get currentPIN => '當前 PIN';

  @override
  String get currentPINRequired => '當前 PIN 是必需的';

  @override
  String get newPIN => '新 PIN';

  @override
  String get newPINRequired => '新 PIN 是必需的';

  @override
  String get confirmPIN => '確認新 PIN';

  @override
  String get pinMismatch => 'PIN 不匹配';

  @override
  String get pinMinLength => 'PIN 必須至少 4 個字符';

  @override
  String get pinUpdated => 'PIN 更新成功';

  @override
  String get iconUpdated => '圖示更新成功';

  @override
  String get generateFromColors => '從顏色生成';

  @override
  String get uploadImage => '上傳圖片';

  @override
  String get backgroundColor => '背景顏色';

  @override
  String get textColor => '文字顏色';

  @override
  String get selectImage => '選擇圖片';

  @override
  String get updatePIN => '更新 PIN';
}
