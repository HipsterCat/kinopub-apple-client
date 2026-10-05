https://api.tvoe.live/shorts?limit=25&skip=0

```
{
    "type": "success",
    "rows": [
        {
            "id": "233a3bce-e712-43af-a88b-4c26373e767e",
            "title": "Побег",
            "coverFileSrc": "/shorts/cover/aa08ee60-f860-40ea-9d78-a3e5cb67a9d6.png",
            "videoFileSrc": "/shorts/video/6abfc73b5729d231734f695d.mp4",
            "videoHlsSrc": "/videos/6abfc747438ff5a2847c4c52",
            "thumbnailSrc": "/images/6abfc7582d3dba1d92ae0136.jpg",
            "isPinnedOnMain": false,
            "link": "https://tvoe.live/p/pobeg",
            "buttonText": "Смотреть",
            "viewsCount": 4621,
            "publishedAt": "2026-10-02T15:01:55.554Z",
            "viewAt": null,
            "movieTitle": "Побег",
            "movieLogo": "/images/67adb729efc61f8f7e25ebdb.png",
            "movieCategory": "serials",
            "movieGenre": "Боевики",
            "movieAgeLevel": 18,
            "movieId": "66f7f35256038149113c387b"
        },
        {...}
    ],
    "total": 403,
    "pagination": {
        "page": 1,
        "limit": 25,
        "totalPages": 17
    }
}
```

https://api.tvoe.live/v2/catalog?categoryAlias=films&limit=100

```
{
    "totalSize": 3012,
    "items": [
        {
            "_id": "6ab52ae1a43b986ad1907cc3",
            "name": "Вдовец: Пока смерть не разлучит нас",
            "shortDesc": "За обаятельной улыбкой и образом идеального супруга скрывается опасный преступник. Журналист и детектив расследуют череду подозрительных смертей и неудачных браков, пытаясь раскрыть правду о мужчине, чьи жёны одна за другой погибали при загадочных обстоятельствах.",
            "ageLevel": 18,
            "dateReleased": "2026-09-30",
            "categoryAlias": "films",
            "badge": {
                "type": "premiere",
                "startAt": "2026-10-03T00:00:00.000Z",
                "finishAt": "2026-10-10T00:00:00.000Z"
            },
            "cover": {
                "src": "/images/6abcde322394f6ca8b35cdf4.jpg"
            },
            "poster": {
                "src": "/images/6abcdf4c47eec1a6e2b54100.jpg"
            },
            "rating": 8.8,
            "countries": "США",
            "duration": 5496.296,
            "seasonsCount": null,
            "url": "/p/vdovec-poka-smert-ne-razluchit-nas"
        },
        {...}
    ]
}
```

https://api.tvoe.live/v2/catalog/filters
```
	1	{films: {,…}, serials: {,…}}
	1	 films :  {,…} 
	1	 countries :  [{name: "Германия", countryCode: "DE"}, {name: "США", countryCode: "US"},…]   genres :  [{name: "Аниме", alias: "anime"}, {name: "Биографии", alias: "biografii"},…]   years :  [1940, 1942, 1946, 1950, 1955, 1957, 1959, 1960, 1961, 1962, 1963, 1964, 1965, 1966, 1967, 1968, 1969,…] 
	2	 serials :  {,…} 
	1	 countries :  [{name: "Польша", countryCode: "PL"}, {name: "Великобритания", countryCode: "GB"},…]   genres :  [{name: "Аниме", alias: "anime"}, {name: "Биографии", alias: "biografii"},…]   years :  [1940, 1967, 1971, 1972, 1976, 1981, 1987, 1989, 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999,…] 

```

https://api.tvoe.live/v2/catalog?categoryAlias=serials&limit=100
```
{
    "totalSize": 1468,
    "items": [
        {
            "_id": "6a0c350f1910d721c17d77dd",
            "name": "Фонари",
            "shortDesc": "Два межгалактических полицейских оказываются вовлечены в загадочное расследование убийства, произошедшего в сердце Америки.",
            "ageLevel": 18,
            "dateReleased": "2026-08-16",
            "categoryAlias": "serials",
            "badge": {
                "type": "premiere",
                "startAt": "2026-10-05T00:00:00.000Z",
                "finishAt": "2026-10-12T00:00:00.000Z"
            },
            "cover": {
                "src": "/images/6abe4ef5da003600ac79e0f7.jpg"
            },
            "poster": {
                "src": "/images/6abe4eeff79fa67c3fa83e1f.jpg"
            },
            "rating": 9.3,
            "countries": "США",
            "duration": 25512.535999999996,
            "seasonsCount": 1,
            "url": "/p/fonari"
        },
        {...}]}
```



