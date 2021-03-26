/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the view controller showing available video assets.
*/

import UIKit
import Photos

class AssetsViewControllerCell: UICollectionViewCell {
    class var reuseIdentifier: String {
        return "AssetCell"
    }
    var representedAssetIdentifier: String = ""
    
    @IBOutlet weak var imageView: UIImageView!
}

// UITableViewController是UICollectionView的一种特殊情况
class AssetsViewController: UICollectionViewController {

    class var showTrackingViewSegueIdentifier: String {
        return "ShowTrackingView"
    }
    
    //从照片库返回的集合，资产(范型)
    //PHAsset照片库中照片，视频资源的表示形式
    var assets: PHFetchResult<PHAsset>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 函数（请求照片库访问许可）
        PHPhotoLibrary.requestAuthorization { (status) in
            // 已授予访问照片库的权限
            if status == .authorized {
                DispatchQueue.main.async {
                    // 从图像库中加载视频资源
                    self.loadAssetsFromLibrary()
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.recalculateItemSize()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    private func loadAssetsFromLibrary() {
        // 返回结果的过滤，排序管理
        let assetsOptions = PHFetchOptions()
        // include all source types
        assetsOptions.includeAssetSourceTypes = [.typeCloudShared, .typeUserLibrary, .typeiTunesSynced]
        // show most recent first（排序：根据最新修改顺序）
        assetsOptions.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        // fecth videos
        assets = PHAsset.fetchAssets(with: .video, options: assetsOptions)
        
        // setup collection view
        self.recalculateItemSize()
        self.collectionView?.reloadData()
    }
    
    private func recalculateItemSize() {
        if let collectionView = self.collectionView {
            //通过布局对象layout配置方式进行布局（流水布局）
            guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
                return
            }
            // 紧凑型
            let desiredItemCount = self.traitCollection.horizontalSizeClass == .compact ? 4 : 6
            
            var availableSize = collectionView.bounds.width
            let insets = layout.sectionInset
            availableSize -= (insets.left + insets.right)
            availableSize -= layout.minimumInteritemSpacing * CGFloat((desiredItemCount - 1))
            let itemSize = CGFloat(floorf(Float(availableSize) / Float(desiredItemCount)))
            if layout.itemSize.width != itemSize {
                layout.itemSize = CGSize(width: itemSize, height: itemSize)
                layout.invalidateLayout()
            }
        }
    }

    private func asset(identifier: String) -> PHAsset? {
        var foundAsset: PHAsset? = nil
        self.assets?.enumerateObjects({ (asset, _, stop) in
            if asset.localIdentifier == identifier {
                foundAsset = asset
                stop.pointee = true
            }
        })
        return foundAsset
    }
    
    // MARK: - Navigation(跳转前的准备工作，主要是传值)
    // MARK: - performSegue()中sender传来来的值（videoAsset音频，视频抽象类）
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == AssetsViewController.showTrackingViewSegueIdentifier {
            guard let avAsset = sender as? AVAsset else {
                fatalError("Unexpected sender type")
            }
            // 目标视图控制器
            guard let trackingController = segue.destination as? TrackingViewController else {
                fatalError("Unexpected destination view controller type")
            }
            /// TrackingViewControllers的属性值变化
            trackingController.videoAsset = avAsset
        }
    }

    // MARK: - UICollectionViewDataSource(协议1)
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let assets = self.assets else {
            return 0
        }
        return assets.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let asset = assets?[indexPath.item] else {
            fatalError("Failed to find asset at index \(indexPath.item)")
        }

        let genericCell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetsViewControllerCell.reuseIdentifier,
                                                             for: indexPath)
        guard let cell = genericCell as? AssetsViewControllerCell else {
            return genericCell
        }
        cell.representedAssetIdentifier = asset.localIdentifier
        let imgMgr = PHImageManager()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        imgMgr.requestImage(for: asset, targetSize: cell.bounds.size, contentMode: .aspectFill, options: options) { (image, options) in
            if asset.localIdentifier == cell.representedAssetIdentifier {
                cell.imageView.image = image
            }
        }
        return cell
    }
    
    // MARK: - UICollectionViewDelegate（协议2）
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AssetsViewControllerCell else {
            fatalError("Failed to find cell as index path \(indexPath)")
        }
        let assetId = cell.representedAssetIdentifier
        guard let asset = self.asset(identifier: assetId) else {
            fatalError("Failed to find asset with identifier \(assetId)")
        }
        //生成预览缩略图
        let imgMgr = PHImageManager.default()
        // 配置从PHImageManager获取资源传递（是否可接入网下载icloud视频， 是否高质量视频）
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .highQualityFormat
        
        //最后为一逃逸闭包（加载i资源完成后执行）
        imgMgr.requestAVAsset(forVideo: asset, options: videoOptions) { (avAsset, _, _) in
            guard let videoAsset = avAsset else {
                return
            }
            DispatchQueue.main.async {
                // 页面跳转，先执行，后结束（ 先调用prepare() ）（通过跳转操作标识符）
                self.performSegue(withIdentifier: AssetsViewController.showTrackingViewSegueIdentifier, sender: videoAsset)
            }
        }
    }
}
