-- Place pages 02: the new place rows get their Apple Maps id (BP app docs/plans/place-pages/issues/02).
-- Apple Maps decides a closing (Jesse, 2026-11-01); the morning finish reads each id's page and hides a
-- place Apple calls Permanently Closed. Lines from `python3 sources/scripts/apple_maps.py match` on this
-- Mac (MapKit), 2026-11-08, over the 269 open places without an id: 126 matched (a 127th, Casey's General Store,
-- lost its row the same day: Jesse, there's no Casey's in town)
-- (name = Apple's name, metres from our pin), 142 with no Apple Maps place near their pin that carries
-- their name, listed at the end; they fall back on Google's monthly closed list.
update public.places set apple_place_id = 'I930716DE5BCEB2FF' where id = '2d652189-e2cc-4d30-8a62-2afaa92822d5';  -- 2nd Avenue Cuts = 2nd Avenue Cuts (15 m)
update public.places set apple_place_id = 'I1D1E2C9825F74387' where id = '99d2b66f-0595-4db1-9f93-dea1b7ef365e';  -- A New Direction = A New Direction (2 m)
update public.places set apple_place_id = 'IE02DC1A0E3065817' where id = '36f885a3-eb93-4409-9c53-1284354ded22';  -- Adam McArthur Agency LLC = Adam McArthur Agency LLC American Family Insurance (0 m)
update public.places set apple_place_id = 'I16AFA48AF81F0A20' where id = '8e6c4571-7fc9-44d4-9904-7a0f883bae48';  -- Amcon Block & Precast = Amcon Block & Precast (16 m)
update public.places set apple_place_id = 'I97637ACE5EF219F1' where id = '2f215f25-ad7e-47c8-b3c1-a8256a24a73e';  -- Angel's Touch Massage = Angel's Touch Massage (8 m)
update public.places set apple_place_id = 'IF551E9AE7EB00F26' where id = '1ba76410-6ca4-4bcd-bc6e-bf9c05eb6803';  -- Angela Larcom Counseling = Angela Larcom Counseling (7 m)
update public.places set apple_place_id = 'I7D639E44D04D2E86' where id = '8abc0cac-3184-4ae4-b349-27249ce5a7c8';  -- Arlington Place of St Joseph = Arlington Place of St Joseph (11 m)
update public.places set apple_place_id = 'IF50CA79CB0D8D8DF' where id = '08fca0f1-105a-4380-957f-701387e6b394';  -- Artisan Renovation & Design = Artisan Renovation & Design (46 m)
update public.places set apple_place_id = 'I456D25D3DDEA626' where id = 'b7f97024-7282-4288-9245-b7aa843a52d4';  -- Audio Video Extremes = Audio Video Extremes (5 m)
update public.places set apple_place_id = 'I7F6D159A183E4DCB' where id = '75555b41-25ba-4010-acd8-d8e6089cf09d';  -- Bee Line Auto & Sport = Bee Line Auto & Sport (17 m)
update public.places set apple_place_id = 'IBDD0AB245BCDB14A' where id = '22a24796-192c-4f04-bce9-61f3ff8e5756';  -- Best-Way Fabricating = Bestway Fabricating (156 m)
update public.places set apple_place_id = 'IDCC9A66383E14887' where id = '27e4bd26-6a38-4c1a-bb00-42f885f0134d';  -- Birchwood Electric, Security and Home Technology = Birchwood Electric, Security & Home Technology (5 m)
update public.places set apple_place_id = 'I5154965F7FB0BF81' where id = 'ca3122ba-feee-4c47-9ad0-e37abaff6f9e';  -- BL Grafx = BL Grafx (16 m)
update public.places set apple_place_id = 'I97F7EF1D1E6EA65E' where id = 'dbd9ce43-f85a-423b-ba28-ca9537e1c5d2';  -- Bliss Direct Media = Bliss Direct Media (61 m)
update public.places set apple_place_id = 'IEDE25824C934119' where id = 'c1331513-9c25-495d-ae38-e3a0c703570e';  -- Bloom Styling & Events = Bloom Styling & Events (0 m)
update public.places set apple_place_id = 'I674CB7365C912433' where id = 'ebb11f5a-e6bf-4658-bf61-0e103da210d8';  -- Boulder Ridge Apartments = Boulder Ridge Apartments (45 m)
update public.places set apple_place_id = 'I177691FD422A0FD9' where id = '693c32aa-96d7-43dc-895b-3b99215bfb7a';  -- Breth-zenzen Fire Protection = Breth-Zenzen Fire Protection (15 m)
update public.places set apple_place_id = 'IE6F451BAEA9BA75B' where id = '67e88d23-c89e-4f46-a579-1dd5f1caff7c';  -- Brush & Roll Painting & Deck Refinishing = Brush & Roll Painting & Deck Refinishing (27 m)
update public.places set apple_place_id = 'I70D5DB685728B039' where id = '147cfd74-3699-4a65-8be0-6e9f35c7706b';  -- Capital Storage Rental of St Joseph = Capital Storage Rental (65 m)
update public.places set apple_place_id = 'I725C077EF17CB263' where id = '6912266d-af1d-44fc-a929-ab70aa27fa64';  -- Caribou Coffee = Caribou Coffee (2 m)
update public.places set apple_place_id = 'I78B3F002501EB3CA' where id = 'f9c8c12e-bbd9-466c-aaad-0fd7ab65e7ef';  -- Carlson Crossing Townhomes = Carlson Crossing Town Homes (6 m)
update public.places set apple_place_id = 'IAEE78A888B097BC5' where id = '857e71d9-179c-4384-892c-0e5afe6f5172';  -- Chem-Dry of St. Cloud = Chem-Dry (41 m)
update public.places set apple_place_id = 'I36B96C1B6867918F' where id = 'a4753fd1-f16b-4e91-b735-d4c1cf9e03bb';  -- Clemens Library = Clemens Library at College of St Benedict (66 m)
update public.places set apple_place_id = 'I3425D5B114BE1307' where id = 'cbd3dec1-e1ed-4aa7-b32d-a02f7ae4ff8d';  -- Coborn's Grocery Store = Coborn's (5 m)
update public.places set apple_place_id = 'I8141F97937FA9900' where id = 'ca5e86c5-0d61-45c7-bd08-b0ab97892463';  -- College of Saint Benedict = College of Saint Benedict (415 m)
update public.places set apple_place_id = 'IF39A5A62B6F87FE6' where id = '8bd0ab4a-083c-4a49-a98b-3e147b3673a3';  -- Collegeville Brokerage = Collegeville Brokerage (33 m)
update public.places set apple_place_id = 'I2257C4024DC3560C' where id = '1d0480f5-451d-47ff-b148-b826c15c531c';  -- Collegeville Orchards = Collegeville Orchards (52 m)
update public.places set apple_place_id = 'I6625933DB433614C' where id = '5f139e42-6a24-42a2-b850-f6d613b5a932';  -- Computer Repair Unlimited = Computer Repair Unlimited (3 m)
update public.places set apple_place_id = 'IA964C687316D940A' where id = 'a107436a-d8d5-4ea8-9d2d-a4f3fef41362';  -- Consumer Directions = Consumer Directions Inc. (CDI) (71 m)
update public.places set apple_place_id = 'IDB7166199C49E54B' where id = '3b6dfb94-17d1-44c1-8ec2-1a8fc7421283';  -- Crafted Skin Clinic = Crafted Skin Clinic (30 m)
update public.places set apple_place_id = 'IA6DD15AE9BE086B9' where id = 'a939d62b-c520-4c3d-b08d-c2f72cbef91c';  -- Creations In Candles = Creations In Candles (17 m)
update public.places set apple_place_id = 'I9F89C545B1A5115C' where id = '38428e37-7450-411e-96be-4e30136073a4';  -- Daniel Funeral Home = Daniel Funeral Home (521 m)
update public.places set apple_place_id = 'ICF441FEC19684E7E' where id = 'd15271cf-d0b7-40a9-81f7-9d03be63d497';  -- Darling Dog Care = Darling Dog Care (2 m)
update public.places set apple_place_id = 'IE2C44E121612E17B' where id = '239ff7cd-547c-408c-bf33-abf6dbc2faa2';  -- Diamond Energy Systems = Diamond Energy Systems (22 m)
update public.places set apple_place_id = 'IEF057CB097F28DFB' where id = '5c7fe0f2-5e2f-465a-af42-6f53f12d7a2d';  -- DKT Auto & Diesel Repair = DKT Auto & Diesel Repair LLC (17 m)
update public.places set apple_place_id = 'IA511F032BB07F5C9' where id = 'cda266ce-80de-4926-a774-1e87305f874e';  -- Dollar General = Dollar General (24 m)
update public.places set apple_place_id = 'I48017A0182EC13C4' where id = '8fa73a98-b979-48a4-8dab-8c47ba7b0af1';  -- Edward Jones = Edward Jones - Financial Advisor: Beau Hanowski, CFP (0 m)
update public.places set apple_place_id = 'I41A9D17A81D216AE' where id = '81d6aa30-92e8-4600-a78a-ff287b7a579f';  -- Ehlinger Lawn Service = Ehlinger Lawn Service (18 m)
update public.places set apple_place_id = 'I9B2FABF5522EC67B' where id = '06b987cc-dbc9-4aa6-ae86-b66c50efd1ed';  -- EmptyPageStudios = Empty Page Studios (16 m)
update public.places set apple_place_id = 'IE52FB03775F02DF8' where id = 'ad585627-3db3-4222-9cdc-58c7ac1091d1';  -- Episcopal House of Prayer = The Episcopal House of Prayer (2 m)
update public.places set apple_place_id = 'ID22E2859C2B370A6' where id = '3300ea29-3b84-4cf6-a2cb-f5c8df1666d3';  -- Executive Express = Executive Express (169 m)
update public.places set apple_place_id = 'IB71AB6FE558FAD4A' where id = '6e4c1e71-2ca5-4e91-966f-6875a9c14d00';  -- Fieldstone Farm = Fieldstone Farms (1 m)
update public.places set apple_place_id = 'IAD4C3417432EFF1E' where id = '475eda6e-d736-4d6b-b713-9514a7c65bab';  -- Fine Line Entertainment = Fine Line Entertainment (18 m)
update public.places set apple_place_id = 'IB42DDBE86C914313' where id = 'abfabc15-bd2f-487c-bb11-23f5ec514c21';  -- Finken Companies = Finken Companies (0 m)
update public.places set apple_place_id = 'I16EA56F963C258ED' where id = 'e20d342d-eb33-4a9e-8271-d5a49e63df3a';  -- Five Star Transport Solutions = Five Star Transport Solutions (19 m)
update public.places set apple_place_id = 'I847F87CA8F5C5FBF' where id = '33656946-00ef-429a-b864-07f92f2a1c51';  -- Flaten Taxidermy = Ryan Flaten Taxidermy (87 m)
update public.places set apple_place_id = 'IBAE4EB5298DC0E97' where id = '8f8ab5ff-4a8a-4b31-96fd-73b691d287e8';  -- Forest Mushrooms = Forest Mushrooms (8 m)
update public.places set apple_place_id = 'I3A463FE7B7CA70B6' where id = '69904289-5991-428d-9540-6705a1c277ff';  -- Full Circle Water = Full Circle Water (20 m)
update public.places set apple_place_id = 'ID26EC4420E95A39' where id = 'ccf9d822-2959-4627-b617-f917011a9f5e';  -- Geri's Country Kennels = Geri's Country Kennels (1 m)
update public.places set apple_place_id = 'IE4A45FB194206422' where id = '871c3e31-89f2-460c-acb7-f7f47109d861';  -- GM Drilling = GM Drilling (319 m)
update public.places set apple_place_id = 'I2CCACA85C8728103' where id = '5d79f380-9342-43ba-a167-bb4e578c2ebc';  -- Gold Country Trucking = Gold Country Trucking (74 m)
update public.places set apple_place_id = 'I72528F09BE9A271F' where id = '266855b3-6c1a-4fa8-b33f-19103e9d26b4';  -- Golden Hill Doodles = Golden Hill Doodles (180 m)
update public.places set apple_place_id = 'IB1C7060975B18038' where id = '5cf1fecf-25e0-44a0-a1d4-fa796f3a494f';  -- Golden Rule Real Estate = Golden Rule Real Estate Services (13 m)
update public.places set apple_place_id = 'I92946801F33C275' where id = '8adb454d-dddb-4310-bcaa-ee4eb1159b55';  -- Granite City Motor Car = Granite City Motor Car (8 m)
update public.places set apple_place_id = 'IE9CE7E35786DCA87' where id = 'b843e372-c9e1-44e1-bed0-fe255251d58e';  -- Grey Face Rescue & Retirement = Grey Face Rescue & Retirement (18 m)
update public.places set apple_place_id = 'IA0803BE37FB3D0F7' where id = '8c5554b3-c402-417f-a931-542c9563cf35';  -- Gutter Shutter of St. Cloud = Gutter Shutter of St. Cloud (85 m)
update public.places set apple_place_id = 'I7C36E44079C5974C' where id = 'c4f573dc-0192-4bda-854c-65de056efb46';  -- Heirborn Kennels = Heirborn Kennels (8 m)
update public.places set apple_place_id = 'IAB3E6547361B922' where id = 'c4455937-b934-4ead-af36-7a2014402a9b';  -- Hemker Park & Zoo = Hemker Park & Zoo (144 m)
update public.places set apple_place_id = 'IEC6AE91A6AF26153' where id = '24dae40d-c157-416b-8005-f0751a5d4ab9';  -- Hi-tec Electric = Hi Tec Electric (10 m)
update public.places set apple_place_id = 'I40E3E5B1FA4E61F9' where id = '37d6cc25-defb-4f47-8e54-9715e5c63289';  -- Huls Bros Trucking Inc = Huls Brothers Trucking (32 m)
update public.places set apple_place_id = 'IEE57702C5102129D' where id = '7b92500c-3486-427b-9fd1-fbfd5be4592f';  -- Interstate Bearing Systems = Interstate Bearing Systems (21 m)
update public.places set apple_place_id = 'I3CAD0547BF7DE81' where id = 'cecdc1a5-0c79-4ffd-afe4-15c4f2f0540b';  -- J.G. Auto Detail = J G Auto Detail (1 m)
update public.places set apple_place_id = 'IC20B4A7DCC006E9D' where id = 'f33591a2-1bce-4770-9ca5-ca43a1eec039';  -- John Mondloch Remodeling = John Mondloch Remodeling (20 m)
update public.places set apple_place_id = 'I4142C52FB43C8056' where id = 'ece69fcd-c1f1-4dcf-acfa-57a4bb5e80d7';  -- Justina Massage = Justina Massage (6 m)
update public.places set apple_place_id = 'I861C2306411AFB68' where id = '07685957-4965-43a1-92a4-94d9c158f917';  -- Kennedy Community School = Kennedy Community School (34 m)
update public.places set apple_place_id = 'I7953A3AA09F1915' where id = '41f48914-db1c-4577-b86f-a7681192cd6b';  -- Kidstop = Kidstop Kennedy (11 m)
update public.places set apple_place_id = 'IFB575554455C32BF' where id = '3238ac6f-158c-4d4c-bb15-5bbd0fd62ac2';  -- King's Kennels = King's Kennels (402 m)
update public.places set apple_place_id = 'IBF6DAAD88ADF95A6' where id = 'd76fc99f-8890-4ae9-85a4-bded16ebf3a1';  -- Klein Builders = Klein Goerger Builders (185 m)
update public.places set apple_place_id = 'I3C56E3BFC844AEFE' where id = '68121630-7e9c-43ba-b7ba-8a49e934ed02';  -- Klinefelter Park = Klinefelter Park (101 m)
update public.places set apple_place_id = 'IB6865125F5D8B81C' where id = 'fa4e2d80-2047-41ad-a208-038a5c8b4e41';  -- Kostreba Appliance Services Center = Kostreba Appliance Services Center (24 m)
update public.places set apple_place_id = 'I2C60CE4A4C969F0' where id = '36f0e6e8-dd62-4e3c-b387-82771435cf73';  -- Kraemer Lake-Wildwood County Park = Kraemer Lake-Wildwood County Park (93 m)
update public.places set apple_place_id = 'I4931C90F65BF165E' where id = 'b7bf46dc-fad7-4220-80ef-4f89c6bb6fe0';  -- Kwik Trip = Kwik Trip (13 m)
update public.places set apple_place_id = 'IBA137C07735A7776' where id = '793fa225-28e3-4a16-944d-15e3ca9ee518';  -- Lookin Good Tint = Lookin Good Tint (25 m)
update public.places set apple_place_id = 'I11B303F9A4927FDB' where id = '939dc72f-eca6-4c66-90d5-71619d031a49';  -- Mainstay = Mainstay Insurance (28 m)
update public.places set apple_place_id = 'IE15B6F9D4F10C825' where id = '13423644-3734-4af2-be52-9dc0d883cc39';  -- McDonald's = McDonald's (8 m)
update public.places set apple_place_id = 'I19C003D77AEDA6CF' where id = '06096a2b-0845-417d-a9b3-f30ad6aefb8a';  -- Memorial Park = Memorial Park (26 m)
update public.places set apple_place_id = 'I2DC4C1AABABCBD5' where id = 'ae5e2bd6-a25c-49a4-83d7-d2a87d27eb07';  -- Meyer Farm Project = Meyer Farm Project (107 m)
update public.places set apple_place_id = 'I1992715BDE5EA121' where id = '12011604-44c0-465b-b43d-b23138899f1e';  -- Mike's Electric = Mike's Electric (29 m)
update public.places set apple_place_id = 'I5BBA0F8214028EC8' where id = '17bdb5d8-52e5-48b4-9f05-124c7043dc99';  -- Mill Stream Village = Mill Stream Village (70 m)
update public.places set apple_place_id = 'I720799C8A4FAA8A2' where id = 'ab521488-ccec-42c8-885d-fcac4ff1cd97';  -- Millstream Park = Millstream Park (263 m)
update public.places set apple_place_id = 'I833C09950DFAEAF2' where id = '19254127-9a6b-4ed5-a006-ddb360f9e6e4';  -- Minnesota Home Improvements = Minnesota Home Improvements (77 m)
update public.places set apple_place_id = 'IF0E71137CEA98355' where id = 'dbdd2050-5e8e-47d3-a91d-19669a89a198';  -- Mission Nutrition = Mission Nutrition (14 m)
update public.places set apple_place_id = 'I2359BADCB37E37F' where id = 'd7e81cf4-f51e-4f07-b07a-c56602da06ae';  -- MN HEAVY TOWING = Mn Heavy Towing (67 m)
update public.places set apple_place_id = 'I7C01C3A4692D4AD8' where id = '8caa276e-c50a-4be3-b96f-a62d152254bc';  -- Municipal Athletic Complex = Municipal Athletic Complex (132 m)
update public.places set apple_place_id = 'I2BCE602BC4B1C238' where id = '77e6fc69-bc25-4890-9152-f880afc47e40';  -- O'Reilly Auto Parts = O'Reilly Auto Parts (0 m)
update public.places set apple_place_id = 'I66BA7F2EA260434' where id = '4af5c137-0357-41f8-99a6-df0229f8180b';  -- Paul Eisenschenk-LakePlace.com = Paul Eisenschenk-LakePlace.com (136 m)
update public.places set apple_place_id = 'I3A54E2702535AC73' where id = 'a61cb1e2-e4ea-4247-97f3-7c10fe872183';  -- Petrek Law Office = Petrek Law Office (43 m)
update public.places set apple_place_id = 'I9663AE90864E9EA6' where id = '73cd8f4c-63e3-431b-bd07-386ba27d97c6';  -- PrairieScapes = PrairieScapes (161 m)
update public.places set apple_place_id = 'I62C6DB77CE26408' where id = '6b498d70-fbc4-4a05-bbfd-4e9499fc4af8';  -- Precise Heating, A/C, Plumbing & Refrigeration = Precise Heating, A/C, Plumbing (5 m)
update public.places set apple_place_id = 'IC4BE148433FA7C8C' where id = '72d65be0-3f00-4d11-96d5-66259ca589fc';  -- Precision Motorsports = Precision Motorsports (14 m)
update public.places set apple_place_id = 'I7E91FD92D9D77C29' where id = 'd0d6f06b-5ba3-4ed2-8c15-4c18ba26ebd8';  -- Premier Stone Design = Premier Stone Design (66 m)
update public.places set apple_place_id = 'IBA1A030AAA48BC1D' where id = 'fc17805b-840b-4237-b007-fc94d799d958';  -- Pro-Tech Forklift Service Inc. = Pro-Tech Forklift Service Inc. (221 m)
update public.places set apple_place_id = 'IA1DA55CBC4A1F111' where id = '87ea5354-b42a-45c6-af1f-edf31f1f44d0';  -- Promotional Resources = Promotional Resources Inc. (36 m)
update public.places set apple_place_id = 'I2BD11DC2A20DF162' where id = 'bac12ac6-5bbb-4902-80af-99d85fd92b3b';  -- Quill & Disc = Quill & Disc (31 m)
update public.places set apple_place_id = 'IA9B92E89D06EB7EB' where id = 'b424053a-b995-4941-bef6-f784f6d26da6';  -- Resurrection Lutheran Church = Resurrection Lutheran Church (9 m)
update public.places set apple_place_id = 'IC3B86B2A21F3F826' where id = '5776a612-3a07-4040-b134-bd53ae06be57';  -- Rockhouse Productions = Rockhouse Productions (17 m)
update public.places set apple_place_id = 'I452C72BC17AEE291' where id = 'e1e76975-9f79-4a76-b8f0-4d7675637d3f';  -- Rolling Ridge Wedding & Event Center = Rolling Ridge Wedding & Event Center (73 m)
update public.places set apple_place_id = 'I8D6EF1AFDAAD1481' where id = '66f39423-a657-4805-b67f-ce08b2976626';  -- Ross Nesbit Agencies = Ross Nesbit Agencies St. Joseph (6 m)
update public.places set apple_place_id = 'IFFD92B07648E74B0' where id = 'ef2070df-3774-47d1-9476-b9fee469dd1e';  -- Rpm Athletics = RPM Athletics (15 m)
update public.places set apple_place_id = 'IB125D14778359404' where id = 'c13c8862-6d97-45c8-b7af-1a5f82b38c69';  -- Russell Eyecare & Associates = Russell Eyecare & Associates (10 m)
update public.places set apple_place_id = 'ICDC1DCEE1ABEA56E' where id = '55bcb1b1-528c-4b16-8d3a-f03cfa80d0e5';  -- Rustic River Gear = Rustic River Gear (0 m)
update public.places set apple_place_id = 'I4079F4A8CADD399A' where id = 'dbb59b00-0d35-47f1-bd38-86e76f999893';  -- Saint John's Abbey = Saint John's Abbey Church (2 m)
update public.places set apple_place_id = 'I756AADCF0AAE2DE9' where id = '6d70ca7d-5649-4697-b81a-2e8943ae358c';  -- Saint John's University = Saint John's University (186 m)
update public.places set apple_place_id = 'I3C10058090E1CA9' where id = 'b3a0852d-7381-41af-b2a4-074abaca228f';  -- Saint Joseph Police Department = Saint Joseph Police Department (468 m)
update public.places set apple_place_id = 'IB2880188AB3C6B65' where id = 'a08023b2-b6fa-40c7-9e9f-f24f34ea8855';  -- Scenic Specialties Landscape Professionals = Scenic Specialties Landscape Professionals (595 m)
update public.places set apple_place_id = 'I2A12C46DD089736' where id = '1958a7b1-81d0-4a8f-aef9-13960dc57148';  -- Scheels Athletic Complex = Scheels Athletic Complex (5 m)
update public.places set apple_place_id = 'I2BCB7B6CF91563FF' where id = 'f7b88602-2f4a-48f5-a44a-0f89dc167142';  -- Scherer Trucking and Sons = Scherer Trucking and Sons (52 m)
update public.places set apple_place_id = 'I32CB30C22643555F' where id = 'fe723b4c-a4ff-4c85-9344-ebe3dc353aa1';  -- Serenity Place on 7th = Serenity Place On 7th Assisted Living (46 m)
update public.places set apple_place_id = 'I22D90E660269E40B' where id = 'fc62d1e0-7488-42be-9b45-5662582c9b4e';  -- Snap Fitness = Snap Fitness (113 m)
update public.places set apple_place_id = 'I52935FE9942F2F0D' where id = '4f401f61-79f4-4697-813c-5b65bed50e39';  -- Sound Connection = Sound Connection (261 m)
update public.places set apple_place_id = 'I230718F78646F1FD' where id = 'b921ba1f-b236-47af-8aa9-4c7eb8ad3259';  -- St Joe Mini-Storage = St. Joe Mini Storage (32 m)
update public.places set apple_place_id = 'I4E60607A23033C77' where id = 'ad8f5dbe-07af-46a3-b76e-c2af9cbd6b33';  -- St John the Baptist Parish = St John the Baptist Parish (37 m)
update public.places set apple_place_id = 'IED7AB2CC1039EE9F' where id = '34b0022c-cd8c-452e-9099-fd723fcb94a8';  -- St. Cloud Acoustics = St Cloud Acoustics (23 m)
update public.places set apple_place_id = 'ICA7A775A316EE441' where id = '4602d253-49b9-41ff-8386-dabd6786791a';  -- St. Cloud Area School District 742 = St. Cloud Area School District 742 (150 m)
update public.places set apple_place_id = 'I2B367C46B2DA7617' where id = 'a4c5cd52-7087-43f7-9ed3-f0c582c72b03';  -- St. Joseph Catholic School = St. Joseph Catholic School (6 m)
update public.places set apple_place_id = 'I63CC9F1E5529CE17' where id = '6eceebf6-a684-498e-971e-7ee2e4342ba8';  -- Stearns Electric Association = Stearns Electric Association (11 m)
update public.places set apple_place_id = 'IC3158C68A1641D0B' where id = '4aaf5ddb-15dd-4ca6-941e-cf6a198f421a';  -- Subway = Subway (0 m)
update public.places set apple_place_id = 'IEB65A97006C1D323' where id = '86bb4154-88ba-4200-9e77-9743aab14597';  -- Tamarack Materials = Tamarack Materials (541 m)
update public.places set apple_place_id = 'IACAE76C402F1E4BB' where id = '623f6ff8-a672-4cca-8737-de3dd286a006';  -- Tanner Systems Inc = Tanner Systems (7 m)
update public.places set apple_place_id = 'IA8BD106EFC58F9C2' where id = '4f6a4e83-1e63-4dd2-9f94-9e11f2997114';  -- The Whole You Wellness Collective = The Whole You Wellness Collective (1 m)
update public.places set apple_place_id = 'I6B5968A1CA068E37' where id = 'de953210-bf2d-454d-bd82-fc14cf72ae8f';  -- Traut Companies = Traut Companies (63 m)
update public.places set apple_place_id = 'I4CBDC4D074500FEF' where id = '64b7fce1-f3df-473f-b8ca-3cee24b5c07a';  -- Truck & Trailer 24HR Mobile Repair = Truck & Trailer 24hr Mobile Repair (15 m)
update public.places set apple_place_id = 'I9FA2A624A6BF627D' where id = '4b502cf9-0b67-435d-a28e-f0f18eb7a1e1';  -- Truck Accessories Direct = Truck Accessories Direct (46 m)
update public.places set apple_place_id = 'IFFFB8A99B9407B8C' where id = 'fcf21d57-f622-43a0-9fdb-a3676ffe20df';  -- Victory Nutrition = Victory Nutrition (20 m)
update public.places set apple_place_id = 'I6C9EFB1005F57AD6' where id = '9066cbca-046c-4402-a3ad-9a1ac6de5705';  -- Winters Family Chiropractic = Winters Family Chiropractic (10 m)
update public.places set apple_place_id = 'IAEF67CAC38431CE3' where id = '8059a172-5c1c-48bb-881a-c7c92ae542f8';  -- Yamry Construction = Yamry Construction (0 m)

-- Not on Apple Maps near their pin (home businesses, apartments, parks and a few storefronts Apple lacks
-- or lists without a place id, like American Burger Bar):
-- no Apple Maps place: 24 North: Lofts on College Avenue (6d4b5fc0-17ba-4b94-b36f-2065ff3611e1)

-- no Apple Maps place: 7 Hills Staurolites (ca9e920c-3d82-4e2f-aa1d-cdee9860b915)

-- no Apple Maps place: Adara Home Health (484884fd-04f8-41b9-854e-2df977395443)

-- no Apple Maps place: American Burger Bar (87cd8550-0e48-4c53-82a5-acef01765ed2)

-- no Apple Maps place: American Manufacturing Co Group (56aeb1a0-49f5-422d-843c-ca18ed1860ed)

-- no Apple Maps place: Ami Auction (7e2e69e3-e4a0-45e7-957d-33f36fc246e6)

-- no Apple Maps place: Anfinson Thompson & Company, Pa (e92d5297-b7c7-4614-a2b8-cfcb8eeed4d1)

-- no Apple Maps place: Anne Renee Bridal Co. (e158a998-cb31-484a-b534-b56a9711b6c9)

-- no Apple Maps place: Astech Corp (a6556d18-ecfe-4173-bb54-fba87a14fc27)

-- no Apple Maps place: Autobody 2000 Inc (2f68442e-0399-4ac5-b60d-cc3237fa7746)

-- no Apple Maps place: Avon Ag-Lime (3677bb03-9587-4951-bf14-d068d3946eb5)

-- no Apple Maps place: BDH Service & Performance Inc. (2a03a900-5f1a-48b3-89c9-cf90e9ec522d)

-- no Apple Maps place: Beumer Outdoors (9f3b5315-bd3f-4c3c-96ff-81a3ac7da5e0)

-- no Apple Maps place: Birdie’s Pizza & Garden Bar (9a643552-39cb-47b9-9d21-50fb855b7f7f)

-- no Apple Maps place: Brenny Transportation, Inc. (2e89bbb6-8728-4ae6-8b8b-53c1629ba395)

-- no Apple Maps place: C & L Excavating Inc (193253a9-4d70-4066-baa5-c871502b7ebc)

-- no Apple Maps place: Centennial Park (de0fbfce-efd1-4cac-ad1f-d3f2b9e02adc)

-- no Apple Maps place: Central Canvas Manufacturing (2a3c426a-299e-462e-a78c-6b09988d9ffe)

-- no Apple Maps place: Central Minnesota Detailing (cf7d675b-e1f1-4e87-be8f-dbf696bd2afb)

-- no Apple Maps place: Central Minnesota Prefinish (9d4fd116-dc1f-41c2-be0f-e7a811f59d65)

-- no Apple Maps place: Central MN Realty (3a9a0946-ad17-4d83-9883-6f245a032569)

-- no Apple Maps place: City of St. Joseph Dog Park (bf9fa45b-d6f2-4494-9035-6354dd5ff88a)

-- no Apple Maps place: Cloverdale Park (c8c398b7-2d0c-45b8-9a67-96984ff98c0c)

-- no Apple Maps place: Cole Papers (cad04bf2-1891-4574-8932-444f25ad00bb)

-- no Apple Maps place: Collegeville Communities Llc (d041ee33-c807-4412-9ce6-7baee7eccc1e)

-- no Apple Maps place: Complete Coverage Rental LLC (e991d1fc-afdf-4020-a74b-548031d3d256)

-- no Apple Maps place: Cost Cutters (33af3119-8b13-4ce7-a8c8-e0d6bf4a5532)

-- no Apple Maps place: Creamery Lofts (dc7a3b72-b25b-4312-b16c-b14a8a35bb35)

-- no Apple Maps place: CSB Benedicta Arts Center Galleries (Gorecki Gallery) (cc5cf7ef-2f3a-477f-a1e2-f26c4fd4178e)

-- no Apple Maps place: Curtis Marketing Group (3589fb91-cad0-4f34-826f-2506ad0783e9)

-- no Apple Maps place: Cutters Lawn Service (fcb98f0c-0be8-4da2-91b8-d5c2950faea3)

-- no Apple Maps place: Dancing Bears Company B&B (0e9a700e-9524-48c4-9506-301651151e4b)

-- no Apple Maps place: Deters Accounting and Tax Service (552e72f8-1010-42a2-af3d-78ac06e06b39)

-- no Apple Maps place: DJ's Flower Bar & Tea (9c104ddf-2326-4650-a258-3f011082ac01)

-- no Apple Maps place: Dovetail Design & Remodeling (92dc734e-1882-4552-9326-dd9c017944bd)

-- no Apple Maps place: DSL Saint Joseph (ea2aa75e-ba26-41e2-8604-574f3f90d012)

-- no Apple Maps place: Elite Refrigeration Heating & Air Conditioning (fc39a455-d34d-4f39-bb21-dae0f5c96c11)

-- no Apple Maps place: Emerald Companies (c34a74cc-f2f5-442a-bf66-4d7acbf36799)

-- no Apple Maps place: Fabral (759f20ab-f1df-4139-8cea-82b1ef03a93c)

-- no Apple Maps place: Fifth Gear Repair (97725c16-b0f4-48c5-aa28-e1342797bee2)

-- no Apple Maps place: Grandview Buildings (b820473a-d4f2-41c8-8807-04b9f0aae139)

-- no Apple Maps place: Granite City Window Cleaning Inc (7e2a10d3-3a0c-4610-b265-d8d56ac1f695)

-- no Apple Maps place: Granite Services Llc (51fca472-0b93-410c-bb88-ed13e8a40295)

-- no Apple Maps place: Greater Minnesota Mentoring Academy (dc589a7a-11aa-4f0b-8930-16057d674e7c)

-- no Apple Maps place: Hdc Development Co (055af3a8-e993-4bde-9cd9-ff89ca43b5af)

-- no Apple Maps place: Heartland Door Sales Inc (e507b2ec-b8cf-4653-8260-4eeb2556a174)

-- no Apple Maps place: Heim-kins Rescued Treasures (0afa5fe5-4429-482c-9a66-1babcadb17ab)

-- no Apple Maps place: Heymans Design (4b4dc45e-cf1c-4951-9b53-12cc5dbed0a1)

-- no Apple Maps place: Holistic Flower Farm (3ae99d03-575b-48c9-8fea-49cdd146b81a)

-- no Apple Maps place: Hollow Park (23a0791a-b6b3-4c47-b51c-81e4afe8bfa1)

-- no Apple Maps place: Home Town Title (71571e13-d608-48c8-8755-f3e78bb391a8)

-- no Apple Maps place: Hudson & Company (339de4f9-8cdb-4e9c-8a4d-5a21ea96f86a)

-- no Apple Maps place: illuminet, LLC (eeec74bd-1bcd-49a8-85f8-c0c88111d329)

-- no Apple Maps place: Impressions Hair Studio (76c821f0-bc35-4bad-a706-f4f58be82d3b)

-- no Apple Maps place: Insurance Advisors (eec1f213-8624-4b14-9b00-2a5285e306df)

-- no Apple Maps place: Jet Black (d6f8e86a-b1a2-47df-8840-4fa9329a30aa)

-- no Apple Maps place: JK Monuments LLC* (6e44549e-5e8f-4db7-ace5-78e5af95f1ab)

-- no Apple Maps place: Joetown Apartments (98a07c3b-fbdf-405b-9626-2587be67da61)

-- no Apple Maps place: Joetown Burgers (d2737fe2-749c-4473-8346-35b2c5c774b0)

-- no Apple Maps place: John Kuebelbeck American Legion Post 328 (b8088f9f-a0b8-44ee-a63c-6242e10fe4d8)

-- no Apple Maps place: JR's Mobil & Radiator Repair (a308c256-61f0-4049-a396-d1c835981f03)

-- no Apple Maps place: K & L Lawncare (83c5e2ee-26dc-455c-87a4-5199effe24e4)

-- no Apple Maps place: K Welz Counseling and Coaching (2e814d70-43fd-412e-ba61-515221351b14)

-- no Apple Maps place: K&A Autobody (0b01ef2d-db2d-4253-8ec0-9b7d60f12ccf)

-- no Apple Maps place: KD Performance Horses (46c878e9-02c7-4b98-875e-b0256eb60265)

-- no Apple Maps place: Keltic Konstruction (97a3b4b6-f310-4f39-8253-b7db2926d9b6)

-- no Apple Maps place: King of Hearths (55a56882-1654-42cc-90c5-e7d7414b30b9)

-- no Apple Maps place: Lane Marie Hair (f003989a-d0e0-42a2-9bc1-a418afd4cad6)

-- no Apple Maps place: Leaps and Bounds Childcare & Preschool (6099b965-5720-4596-b9fa-a587d5de20a8)

-- no Apple Maps place: Lillian Leonard Primary (0379d387-8fa8-4262-9cc2-472be0776355)

-- no Apple Maps place: Little Shop Welding & Repair (062aa60c-6a7d-4ceb-b403-69203b9e33b9)

-- no Apple Maps place: Malibu Tan (9e25759d-92dc-4b30-b1a3-7cc786686c14)

-- no Apple Maps place: Mark's Wallcoating Inc (c6e369b7-7243-4196-a3e1-e5de739df60a)

-- no Apple Maps place: Metro Plumbing & Heating, Inc. (7232fa5a-c0fc-4e17-b3a3-2db3f1f4666c)

-- no Apple Maps place: Milbert Johnson Family Dentistry (1b35c7a9-713b-4da7-906e-4f74b0c2cb80)

-- no Apple Maps place: Millan Brothers Construction Inc. (82312049-0114-4587-bb77-b377553e3396)

-- no Apple Maps place: Millstream Communications (8a757cf2-e513-4268-9663-006d4f39bcdb)

-- no Apple Maps place: Minnesota Association of Farm Mutual Insurance Companies (2263ec6e-e353-4ee0-91e6-11f059474245)

-- no Apple Maps place: Minnesota Street Market, Food & Art Co-op (7566738c-0349-4b9e-837b-f0c5ad5ed64e)

-- no Apple Maps place: Monument Park (587e0bea-b1c7-47e7-8d34-8cb2f7a78540)

-- no Apple Maps place: Mortgages on Main (56f21f83-3d64-4bd4-8c6a-a2cb5d1261f6)

-- no Apple Maps place: NAMI Solutions, Inc. (0bfbab6c-b800-4e4a-b9bf-94858eee18ba)

-- no Apple Maps place: North Central Distributing (1754154f-9ba3-423f-a4b9-ba9cdb0e4d8b)

-- no Apple Maps place: Northland Park (43647dd7-4422-4456-990c-4b1ac09e2c5b)

-- no Apple Maps place: Omann Insurance Agency, LLC (a6e854dd-632e-4e84-a6e5-2ce40c753af5)

-- no Apple Maps place: One Hour Heating & Air Conditioning (5d6e7680-19b9-46c7-a984-2e00e710221e)

-- no Apple Maps place: Outlet Bait & Tackle (f4c9cb3c-c830-4811-92b7-54930c6e7c9a)

-- no Apple Maps place: Paquin Seasonal/Self Storage (988787e8-f9f9-436f-a43d-11fca22dedc6)

-- no Apple Maps place: Party Bus (a59358e2-b3fe-498e-8876-ff858da2795f)

-- no Apple Maps place: Paul Kollmann Monuments, LLC (6e44dc98-e027-417c-afd7-96fb6f3c61d6)

-- no Apple Maps place: Pierce Insurance Agency (b4af59d7-0006-4fb7-8ff9-b79bb2e380c4)

-- no Apple Maps place: Piper's Plumbing (d8e5c579-90a7-48bf-aae0-a737b6c10a23)

-- no Apple Maps place: Pristine Environmental (090fc67d-e105-4493-b1fa-4c52bf8cb9bc)

-- no Apple Maps place: River of Life Church (d9f0ce3c-f1d6-429a-be50-3fad14419734)

-- no Apple Maps place: Rivers Bend Cottage Homes (3752c27d-089e-405f-ba2a-44df3e9bc692)

-- no Apple Maps place: Roadway Sport-N-Trailer (f94db88f-1a1b-4be0-8258-28fdaf5e18ba)

-- no Apple Maps place: Rocky Acre Gardens (884bcb4d-fba0-461e-9dcc-be2ea6e72e04)

-- no Apple Maps place: Roger Tamm Photography (f7205b53-fcd2-41ab-939b-21b59d6c9d4b)

-- no Apple Maps place: Rothstein Christmas Tree Farm (2ddcda14-4cc8-4fd0-bd39-9c646b652a4f)

-- no Apple Maps place: Saint Joseph Off Sale Liquor (Hollander's St. Joseph Liquor Shoppe) (8f895259-9d33-412e-bfcb-9adc2605935b)

-- no Apple Maps place: Sam's Outdoor & More (8cf9cef4-8228-4f7f-b0a2-2e8ca35d2be8)

-- no Apple Maps place: Scott Investigation (dda9e5cd-80a9-43f0-b698-0cf07763d462)

-- no Apple Maps place: Sheryl Matters Massage (e47c4da2-b44f-44d2-af68-adb8181634b1)

-- no Apple Maps place: Sisters & Company (81543a4e-cbe0-4ee6-8c2d-0674b3bbe968)

-- no Apple Maps place: Six · Twelve Boutique (b840af0d-7bee-483b-9bdc-c2ec69415c1a)

-- no Apple Maps place: Spectrum Supply Co (e42bd4b3-5618-4fdb-92c9-6af7bddedde3)

-- no Apple Maps place: Speedway (0415257a-03eb-4493-919b-36db7d423069)

-- no Apple Maps place: St Benedicts Art & Heritage (0ef1dcb9-b4ee-4128-b291-4018613865b0)

-- no Apple Maps place: St Joe Rod and Gun Club (6ddc794a-efee-4d85-b3ea-37460ac82eb9)

-- no Apple Maps place: St Joseph Laundromat (43e48963-1a1a-4729-a069-228b83093dcc)

-- no Apple Maps place: St Joseph Manufactured Home Community (f50c9b5f-fc19-4cbc-a8d4-9fedfce1a5db)

-- no Apple Maps place: St Joseph Plumbing Heating & Irrigation (701a8568-2dd0-48c8-a621-1b46bbea8f8d)

-- no Apple Maps place: St. Joseph Blockhouse (27723194-b271-4678-89d6-e5eaabe5eee5)

-- no Apple Maps place: St. Joseph Community Food Shelf (c8c5de45-203b-410b-838b-12f079c0e639)

-- no Apple Maps place: St. Joseph Equine Clinic (f1dabe85-f4a4-4f85-aca9-324a70f82877)

-- no Apple Maps place: St. Joseph Farmers' Market (4a213aca-4735-40dd-9ac4-2b58696a0427)

-- no Apple Maps place: St. Joseph Government Center (b6b0dcc9-7d18-4a50-90a7-3a08de81ef59)

-- no Apple Maps place: St. Joseph Joes (6bf793c3-35ea-47a4-9977-7186d00ed946)

-- no Apple Maps place: St. Joseph Township Hall (699c70a8-2593-43b1-acbf-69d77e072048)

-- no Apple Maps place: St. Joseph Trailhead of Lake Wobegon Trail (1bd04170-3f6d-48ba-b4ed-174458ff2eba)

-- no Apple Maps place: St. Wendel Tamarack Bog Scientific & Natural Area (fb6ad725-598b-48f8-9b26-c00bc6e3a9fa)

-- no Apple Maps place: Steve's Landscape Service (714403af-71bd-413e-9b9f-cd762312323c)

-- no Apple Maps place: Strack Construction Co Inc (9378fdb9-2b34-4403-8201-8b4b73a15241)

-- no Apple Maps place: Straight And Square Distributing Llc (721841a0-fed3-4027-8677-08ceeb993dc5)

-- no Apple Maps place: Sunset Manufacturing / Sunset Equipment (78140694-5c9d-4fba-81e7-1f0140530672)

-- no Apple Maps place: T & R Glass & Woodworks (86de2a03-59db-4deb-bc05-fb30d076e488)

-- no Apple Maps place: Taco John's (682e038a-162b-4111-bb87-475bb8a8a9f9)

-- no Apple Maps place: Tastefully Simple Independent Consultant Lori Tiffany (68224218-70f6-4af5-a392-e9e8cfb190ca)

-- no Apple Maps place: TCC Materials (df226fe1-184e-4f2f-8432-2961e8012f48)

-- no Apple Maps place: The Barn (f44fde55-dba1-4ed5-90cc-2fb59a78d754)

-- no Apple Maps place: The Master Engraving Shoppe (f4739351-dda2-4a98-8374-9453078f4a03)

-- no Apple Maps place: The Newsleaders (b69f0ecb-e938-45a8-861b-87ce92a01710)

-- no Apple Maps place: The North Table (33296a14-4f8d-4e9e-8b2e-88b6c37f1d67)

-- no Apple Maps place: The Oasis Bar and Pit (916f97f5-d309-4ff6-9802-d4b1571ad676)

-- no Apple Maps place: TMT Integrity Flooring, LLC (a976412a-4bc4-4100-8373-4a1ff1357e79)

-- no Apple Maps place: US Army Reserve Training (262e4914-5965-4dcb-b350-ea4634cde6df)

-- no Apple Maps place: V-Twin Tavern (d9cdb2ab-8778-422d-9012-c9a6eabac1ab)

-- no Apple Maps place: W Gohman Construction Co (2ec6b599-8b48-42db-b2f0-3904e34390af)

-- no Apple Maps place: Wendy Loso (15b6a2b8-92df-414f-8dc4-dee05e1aff5e)

-- no Apple Maps place: West Apartments (becbd249-198e-4ff9-ad24-2b2b9bc0b589)

-- no Apple Maps place: Whitby Gift Shop & Gallery (bc27d1cb-ec01-4a70-a084-9948376f8a2a)

-- no Apple Maps place: Wildwood Ranch Maple Syrup (b367e8ab-b872-4142-b814-ecdd4e318d5d)

