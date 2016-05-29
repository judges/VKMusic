//
//  DownloadManager.swift
//  VkPlaylist
//
//  Created by Илья Халяпин on 26.05.16.
//  Copyright © 2016 Ilya Khalyapin. All rights reserved.
//

import UIKit

class DownloadManager: NSObject {
    
    private struct Static {
        static var onceToken: dispatch_once_t = 0 // Ключ идентифицирующий жизненынный цикл приложения
        static var instance: DownloadManager? = nil
    }
    
    class var sharedInstance : DownloadManager {
        dispatch_once(&Static.onceToken) { // Для указанного токена выполняет блок кода только один раз за время жизни приложения
            Static.instance = DownloadManager()
        }
        
        return Static.instance!
    }
    
    
    private override init() {}
    
    
    lazy var downloadsSession: NSURLSession = {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        return session
    }()
    
    private var delegates = [DownloadManagerDelegate]()
    
    // Добавление нового делегата
    func addDelegate(delegate: DownloadManagerDelegate) {
        if let _ = delegates.indexOf({ $0 === delegate}) {
            return
        }
        
        delegates.append(delegate)
    }
    
    // Удаление делегата
    func deleteDelegate(delegate: DownloadManagerDelegate) {
        if let index = delegates.indexOf({ $0 === delegate}) {
            delegates.removeAtIndex(index)
        }
    }
    
    
    var activeDownloads = [String: Download]() { // Активные загрузки (в очереди и загружаемые сейчас)
        didSet {
            // Устанавливаем значение бейджа вкладки "Загрузки"
            ((UIApplication.sharedApplication().delegate as! AppDelegate).window!.rootViewController as! UITabBarController).tabBar.items![1].badgeValue = activeDownloads.count == 0 ? nil : "\(activeDownloads.count)"
        }
    }
    var downloadsTracks = [Track]() // Загружаемые треки (в очереди и загружаемые сейчас)
    
    
    let simultaneousDownloadsCount = 2 // Количество одновременных загрузок
    
    var queue = [Download]() { // Очередь на загрузку
        didSet {
            tryStartDownloadFromQueue()
        }
    }
    var downloadsNow = 0 // Количество треков загружаемых сейчас
    
    // Попытка начать загрузку из очереди
    func tryStartDownloadFromQueue() {
        if !queue.isEmpty && downloadsNow < simultaneousDownloadsCount {
            downloadsNow += 1
            
            let download = queue.first!
            queue.removeFirst()
            
            download.downloadTask!.resume()
            download.isDownloading = true
            download.inQueue = false
            
            downloadUpdated(download)
        }
    }
    
    // Удалить загрузку из очереди
    func deleteFromQueueDownload(download: Download) {
        download.inQueue = false
        
        for (index, downloadInQueue) in queue.enumerate() {
            if downloadInQueue.url == download.url {
                queue.removeAtIndex(index)
                
                return
            }
        }
        
        downloadUpdated(download)
    }
    
    
    // MARK: Загрузка треков
    
    // Новая загрузка
    func downloadTrack(track: Track) {
        if let urlString = track.url, url =  NSURL(string: urlString) {
            let download = Download(url: urlString)
            download.downloadTask = downloadsSession.downloadTaskWithURL(url)
            download.inQueue = true
            
            activeDownloads[download.url] = download // Добавляем загрузку трека в список активных загрузок
            downloadsTracks.append(track) // Добавляем трек в список загружаемых
            
            queue.append(download) // Добавляем загрузку в очередь
            
            downloadUpdated(download)
        }
    }
    
    // Отмена выполенения загрузки
    func cancelDownloadTrack(track: Track) {
        if let urlString = track.url, download = activeDownloads[urlString] {
            download.downloadTask?.cancel() // Отменяем выполнение загрузки
            
            if download.isDownloading {
                downloadsNow -= 1
                tryStartDownloadFromQueue()
            }
            deleteFromQueueDownload(download) // Удаляем загрузку из очереди
            
            popTrackForDownloadTask(download.downloadTask!) // Удаляем трек из списка загружаемых
            activeDownloads[urlString] = nil // Удаляем загрузку трека из списка активных загрузок
            
            downloadUpdated(download)
        }
    }
    
    // Пауза загрузки
    func pauseDownloadTrack(track: Track) {
        if let urlString = track.url, download = activeDownloads[urlString] {
            if download.isDownloading {
                download.downloadTask?.cancelByProducingResumeData { data in
                    if data != nil {
                        download.resumeData = data
                    }
                }
                
                if download.isDownloading {
                    downloadsNow -= 1
                    tryStartDownloadFromQueue()
                }
                deleteFromQueueDownload(download) // Удаляем загрузку из очереди
                
                download.isDownloading = false
                
                downloadUpdated(download)
            }
        }
    }
    
    // Продолжение загрузки
    func resumeDownloadTrack(track: Track) {
        if let urlString = track.url, download = activeDownloads[urlString] {
            if let resumeData = download.resumeData {
                download.downloadTask = downloadsSession.downloadTaskWithResumeData(resumeData)
                download.inQueue = true
                queue.append(download) // Добавляем загрузку в очередь
                
                downloadUpdated(download)
            } else if let url = NSURL(string: download.url) {
                download.downloadTask = downloadsSession.downloadTaskWithURL(url)
                download.inQueue = true
                queue.append(download) // Добавляем загрузку в очередь
                
                downloadUpdated(download)
            }
        }
    }
    
    
    // MARK: Помощники
    
    // Получение трека для указанной загрузки
    func trackForDownloadTask(downloadTask: NSURLSessionDownloadTask) -> Track? {
        if let url = downloadTask.originalRequest?.URL?.absoluteString {
            for track in downloadsTracks {
                if url == track.url! {
                    return track
                }
            }
        }
        
        return nil
    }
    
    // Извлекает загружаемый трек из списка загружаемых треков
    func popTrackForDownloadTask(downloadTask: NSURLSessionDownloadTask) -> Track? {
        if let url = downloadTask.originalRequest?.URL?.absoluteString {
            for (index, track) in downloadsTracks.enumerate() {
                if url == track.url! {
                    downloadsTracks.removeAtIndex(index)
                    
                    return track
                }
            }
        }
        
        return nil
    }
    
    func downloadUpdated(download: Download) {
        delegates.forEach { delegate in
            delegate.DownloadManagerUpdateStateTrackDownload(download)
        }
    }
    
}


// MARK: NSURLSessionDownloadDelegate

extension DownloadManager: NSURLSessionDownloadDelegate {
    
    // Вызывается когда загрузка была завершена
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        
        if let url = downloadTask.originalRequest?.URL?.absoluteString {
            downloadsNow -= 1
            tryStartDownloadFromQueue()
            
            activeDownloads[url] = nil // Удаляем загрузку трека из списка активных загрузок
        }
        
        // Загруженный трек
        let track = popTrackForDownloadTask(downloadTask)! // Извлекаем трек из списка загружаемых треков
        let file = NSData(contentsOfURL: location)! // Загруженный файл
        
        DataManager.sharedInstance.toSaveDownloadedTrackQueue.append((track: track, file: file))
        
        
        delegates.forEach { delegate in
            delegate.DownloadManagerURLSession(session, downloadTask: downloadTask, didFinishDownloadingToURL: location)
        }
    }
    
    // Вызывается когда часть данных была загружена
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        delegates.forEach { delegate in
            delegate.DownloadManagerURLSession(session, downloadTask: downloadTask, didWriteData: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }
    
}